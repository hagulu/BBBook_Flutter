import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_alert.dart';
import '../../../shared/widgets/app_loading.dart';
import 'widgets/camera_control_rotation.dart';

/// 메모 사진 조각용 촬영 화면을 열고, 촬영하거나(좌하단 아이콘으로) 갤러리에서
/// 고른 이미지의 로컬 경로를 반환한다. 취소하면 null.
Future<String?> captureMemoPhoto(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const MemoPhotoCameraScreen(),
    ),
  );
}

/// 메모 사진 조각용 촬영 화면. [MemoOcrCameraScreen]과 카메라 초기화/생명주기
/// 구조는 같지만, OCR 가이드 없이 촬영 결과(또는 갤러리 선택 결과)를 그대로
/// 반환한다.
class MemoPhotoCameraScreen extends StatefulWidget {
  const MemoPhotoCameraScreen({super.key});

  @override
  State<MemoPhotoCameraScreen> createState() => _MemoPhotoCameraScreenState();
}

class _MemoPhotoCameraScreenState extends State<MemoPhotoCameraScreen>
    with WidgetsBindingObserver {
  // BookNoteRepository._maxImageBytes와 같은 값으로 맞춘다 — 저장 계층의
  // 허용치와 어긋나면 여기 통과한 사진이 결국 저장 시점에 거절된다.
  static const _maxPhotoBytes = 5 * 1024 * 1024;

  CameraController? _controller;
  bool _isLoading = true;
  bool _isTakingPicture = false;
  bool _isPickingImage = false;
  String? _errorMessage;
  int _cameraGeneration = 0;

  // 회전 잠금 상태에서도 실제 기기 자세를 알아내 촬영 방향을 맞추고
  // (lockCaptureOrientation), 컨트롤 아이콘 방향도 함께 돌리기 위한 값.
  NativeDeviceOrientation _deviceOrientation =
      NativeDeviceOrientation.portraitUp;
  StreamSubscription<NativeDeviceOrientation>? _orientationSubscription;
  Future<void> _orientationLockChain = Future<void>.value();
  bool _orientationSubscriptionPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _orientationSubscription = NativeDeviceOrientationCommunicator()
        .onOrientationChanged(useSensor: true)
        .listen(_handleOrientationChanged);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_orientationSubscription?.cancel());
    _cameraGeneration++;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  void _handleOrientationChanged(NativeDeviceOrientation orientation) {
    if (!mounted || orientation == _deviceOrientation) return;
    setState(() => _deviceOrientation = orientation);
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      unawaited(
        _queueCaptureOrientationLock(
          controller,
          orientation,
          _cameraGeneration,
        ),
      );
    }
  }

  Future<bool> _queueCaptureOrientationLock(
    CameraController controller,
    NativeDeviceOrientation orientation,
    int generation, {
    bool requirePublishedController = true,
  }) {
    final result = Completer<bool>();
    final lock = _orientationLockChain.then((_) async {
      if (!mounted ||
          generation != _cameraGeneration ||
          (requirePublishedController && !identical(controller, _controller)) ||
          !controller.value.isInitialized) {
        result.complete(false);
        return;
      }
      try {
        await controller.lockCaptureOrientation(
          orientation.deviceOrientation ?? DeviceOrientation.portraitUp,
        );
        result.complete(true);
      } catch (error, stackTrace) {
        developer.log(
          '[메모 사진 카메라 방향 잠금] target=camera '
          'result=FAIL reason=capture_orientation_lock_error',
          error: error,
          stackTrace: stackTrace,
        );
        result.complete(false);
      }
    });
    _orientationLockChain = lock;
    return result.future;
  }

  void _pauseOrientationSensor() {
    if (_orientationSubscriptionPaused) return;
    _orientationSubscription?.pause();
    _orientationSubscriptionPaused = true;
  }

  void _resumeOrientationSensor() {
    if (!_orientationSubscriptionPaused) return;
    _orientationSubscription?.resume();
    _orientationSubscriptionPaused = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _resumeOrientationSensor();
        if (!_isPickingImage) _initializeCamera();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _pauseOrientationSensor();
        _releaseCamera();
        break;
    }
  }

  void _releaseCamera() {
    _cameraGeneration++;
    final controller = _controller;
    _controller = null;
    if (mounted) {
      setState(() => _isLoading = true);
    }
    if (controller != null) unawaited(controller.dispose());
  }

  Future<void> _initializeCamera() async {
    final generation = ++_cameraGeneration;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    CameraController? nextController;
    try {
      final previousController = _controller;
      _controller = null;
      if (previousController != null) await previousController.dispose();
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('camera_not_found');
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      nextController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await nextController.initialize();
      if (!mounted || generation != _cameraGeneration) {
        await nextController.dispose();
        return;
      }
      // 방향 잠금 중 새 센서 값이 들어오면 최신 방향까지 다시 적용한다.
      // 각 await 뒤 세대를 확인해 백그라운드 전환으로 무효화된 컨트롤러가
      // 화면에 다시 게시되지 않게 한다.
      while (true) {
        final orientation = _deviceOrientation;
        final locked = await _queueCaptureOrientationLock(
          nextController,
          orientation,
          generation,
          requirePublishedController: false,
        );
        if (!mounted || generation != _cameraGeneration) {
          await nextController.dispose();
          return;
        }
        if (!locked) throw StateError('capture_orientation_lock_failed');
        if (orientation == _deviceOrientation) break;
      }
      setState(() {
        _controller = nextController;
        _isLoading = false;
      });
      developer.log('[메모 사진 카메라] target=camera result=SUCCESS');
    } catch (error, stackTrace) {
      if (nextController != null) await nextController.dispose();
      if (!mounted || generation != _cameraGeneration) return;
      developer.log(
        '[메모 사진 카메라] target=camera '
        'result=FAIL reason=camera_initialize_error',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() {
        _isLoading = false;
        _errorMessage = '카메라 권한을 확인한 뒤 다시 시도해 주세요.';
      });
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isTakingPicture) {
      return;
    }
    setState(() => _isTakingPicture = true);
    try {
      final file = await controller.takePicture();
      // iOS는 세션 프리셋과 무관하게 정지 사진을 센서 원본 해상도로
      // 찍어, 저장 계층(BookNoteRepository._maxImageBytes와 동일한 값)의
      // 5MB 제한을 넘기는 경우가 드물지 않다 — 여기서 걸러야 사용자가
      // 메모 내용까지 다 쓴 뒤에야 저장 실패로 알게 되는 일을 막는다.
      final sizeBytes = await File(file.path).length();
      if (sizeBytes > _maxPhotoBytes) {
        developer.log(
          '[메모 사진 촬영] target=camera result=FAIL reason=file_too_large',
        );
        unawaited(_deleteFileQuietly(file.path));
        if (mounted) {
          await AppAlert.show(
            context,
            title: '사진 용량이 너무 큽니다',
            message: '5MB 이하로 촬영하거나 갤러리에서 다른 사진을 선택해 주세요.',
          );
        }
        return;
      }
      developer.log('[메모 사진 촬영] target=camera result=SUCCESS');
      if (mounted) Navigator.of(context).pop(file.path);
    } catch (error, stackTrace) {
      developer.log(
        '[메모 사진 촬영] target=camera '
        'result=FAIL reason=take_picture_error',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        await AppAlert.show(
          context,
          title: '사진을 촬영하지 못했습니다',
          message: '잠시 후 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _isTakingPicture = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isPickingImage || _isTakingPicture) return;
    setState(() => _isPickingImage = true);
    String? pickedPath;
    try {
      // 원본을 그대로 반환하면 저장 계층(BookNoteRepository._resolveImageUrl)의
      // jpg/jpeg/png/webp·5MB 제한을 넘기거나(고해상도 원본), iOS 갤러리의
      // 기본 형식(HEIC)이라 형식 자체가 거절될 수 있다 — imageQuality를
      // 지정해 image_picker가 JPEG로 재인코딩하며 크기도 줄이게 한다.
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      developer.log('[메모 사진 갤러리 선택] target=image_picker result=SUCCESS');
      if (mounted && picked != null) {
        pickedPath = picked.path;
        Navigator.of(context).pop(pickedPath);
        return;
      }
    } catch (error, stackTrace) {
      developer.log(
        '[메모 사진 갤러리 선택] target=image_picker '
        'result=FAIL reason=gallery_image_pick_error',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        await AppAlert.show(
          context,
          title: '사진을 불러오지 못했습니다',
          message: '잠시 후 다시 시도해 주세요.',
        );
      }
    } finally {
      // 성공해서 화면이 닫히는 중이면(pickedPath != null) 이미 못 쓰게 될
      // 카메라를 다시 초기화할 필요가 없다 — 선택 중 백그라운드 전환으로
      // 해제된 카메라를 여기서 재획득하면 화면 전환과 리소스 재획득이
      // 경합한다([MemoOcrCameraScreen]의 같은 처리 참고).
      if (mounted && pickedPath == null) {
        setState(() => _isPickingImage = false);
        if (WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            _controller == null) {
          await _initializeCamera();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mediaBackdrop,
      body: AppLoadingOverlay(
        isLoading: _isLoading || _isPickingImage,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller case final controller?)
              // CameraPreview는 Android에서 lockedCaptureOrientation을 읽어
              // 프리뷰 자체를 RotatedBox로 돌린다. 앱 화면은 세로 고정이므로
              // 플랫폼 프리뷰를 세로 비율로 직접 표시해, 촬영 방향과 아이콘만
              // 기기 자세를 따르고 사용자가 보는 프리뷰는 움직이지 않게 한다.
              Center(
                child: AspectRatio(
                  aspectRatio: 1 / controller.value.aspectRatio,
                  child: controller.buildPreview(),
                ),
              )
            else
              const ColoredBox(color: AppColors.mediaBackdrop),
            if (_errorMessage case final message?)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.surface),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _initializeCamera,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 12,
              left: 12,
              child: SafeArea(
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '닫기',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surface.withValues(alpha: 0.84),
                    foregroundColor: AppColors.textStrong,
                  ),
                  icon: RotatedControlIcon(
                    orientation: _deviceOrientation,
                    icon: PhosphorIconsRegular.x,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              bottom: 38,
              child: SafeArea(
                top: false,
                child: IconButton(
                  onPressed: _isTakingPicture || _isPickingImage
                      ? null
                      : _pickFromGallery,
                  tooltip: '갤러리에서 선택',
                  constraints: const BoxConstraints.tightFor(
                    width: 52,
                    height: 52,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surface.withValues(alpha: 0.9),
                    foregroundColor: AppColors.textStrong,
                    disabledBackgroundColor: AppColors.surfaceSubtle,
                    shape: const CircleBorder(),
                  ),
                  icon: RotatedControlIcon(
                    orientation: _deviceOrientation,
                    icon: PhosphorIconsRegular.imageSquare,
                    size: 24,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: SafeArea(
                top: false,
                child: Center(
                  child: IconButton(
                    onPressed: _isTakingPicture ? null : _takePicture,
                    tooltip: '촬영',
                    constraints: const BoxConstraints.tightFor(
                      width: 72,
                      height: 72,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.textStrong,
                      disabledBackgroundColor: AppColors.surfaceSubtle,
                      side: const BorderSide(
                        color: AppColors.highlightGold,
                        width: 4,
                      ),
                      shape: const CircleBorder(),
                    ),
                    icon: RotatedControlIcon(
                      orientation: _deviceOrientation,
                      icon: PhosphorIconsRegular.camera,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _deleteFileQuietly(String path) async {
  try {
    await File(path).delete();
  } catch (_) {
    // 임시 촬영 파일 정리 실패는 사용자 흐름에 영향을 주지 않는다.
  }
}
