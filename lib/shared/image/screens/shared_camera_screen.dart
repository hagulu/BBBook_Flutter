import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_loading.dart';
import '../services/image_gallery_picker.dart';
import '../widgets/camera_control_rotation.dart';

/// 카메라 미리보기를 어떻게 그릴지. 목적마다 다른 결과가 나오는 이유는
/// [SharedCameraScreen]의 클래스 문서를 참고.
enum CameraPreviewMode {
  /// [CameraPreview]를 그대로 쓴다(OCR 촬영 가이드가 이 좌표계를 기준으로
  /// 겹쳐 그려진다).
  direct,

  /// Android의 `CameraPreview`가 잠긴 촬영 방향에 따라 `RotatedBox`로
  /// 미리보기 자체를 돌리는 것을 상쇄하기 위해, 세로 비율로 고정한
  /// `controller.buildPreview()`를 쓴다.
  rotatedAspectRatio,
}

/// 촬영 실패 안내에 쓰는 제목/메시지 쌍.
class CameraCaptureErrorCopy {
  const CameraCaptureErrorCopy({required this.title, required this.message});

  final String title;
  final String message;
}

/// 호출 목적(메모 사진/발췌 OCR 등)에 따라 공용 카메라 화면의 동작을
/// 다르게 만드는 정책. 각 필드는 기존 화면(`MemoPhotoCameraScreen`/
/// `MemoOcrCameraScreen`)이 서로 다르게 구현했던 지점과 1:1로 대응한다 —
/// 겉보기엔 복사-붙여넣기처럼 보이지만 의도적인 차이라 하나로 합치지
/// 않는다.
class CameraCapturePolicy {
  const CameraCapturePolicy({
    this.previewMode = CameraPreviewMode.direct,
    this.guideOverlayBuilder,
    this.hintText,
    this.galleryImageQuality,
    this.galleryMaxWidth,
    this.copyGalleryPickToTemp = false,
    this.tempFilePrefix,
    this.maxCaptureBytes,
    this.captureTooLargeCopy,
  });

  final CameraPreviewMode previewMode;

  /// 미리보기 위에 겹쳐 그릴 가이드(OCR의 수평선 등). 위치·좌표계는
  /// [previewMode]와 맞물려 있으므로 호출부가 직접 그린다.
  final WidgetBuilder? guideOverlayBuilder;

  /// 가이드 아래 안내 문구.
  final String? hintText;

  /// 갤러리 선택 시 재인코딩 품질/최대 너비. 둘 다 비우면 원본 그대로
  /// 받는다(OCR — 인식률을 위해 압축하지 않는다).
  final int? galleryImageQuality;
  final double? galleryMaxWidth;

  /// 갤러리에서 고른 파일을 앱 임시 디렉터리로 복사해 안정된 경로로
  /// 만들지 여부(OCR — 분석이 끝날 때까지 원본이 살아 있어야 한다).
  final bool copyGalleryPickToTemp;
  final String? tempFilePrefix;

  /// 촬영 직후 파일 용량 상한(메모 사진 — 저장 계층의 5MB 제한을 촬영
  /// 시점에 미리 걸러낸다). null이면 검사하지 않는다.
  final int? maxCaptureBytes;
  final CameraCaptureErrorCopy? captureTooLargeCopy;
}

/// 공용 카메라 화면을 열고 촬영/갤러리 선택 결과의 로컬 경로를 반환한다.
/// 취소하면 null.
Future<String?> showSharedCameraScreen(
  BuildContext context, {
  required CameraCapturePolicy policy,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SharedCameraScreen(policy: policy),
    ),
  );
}

/// 메모 사진·발췌 OCR이 공유하는 촬영 화면. 카메라 초기화/생명주기/방향
/// 잠금은 두 목적이 완전히 같고, [CameraCapturePolicy]로 넘겨받는 지점만
/// 목적별로 달라진다.
class SharedCameraScreen extends StatefulWidget {
  const SharedCameraScreen({super.key, required this.policy});

  final CameraCapturePolicy policy;

  @override
  State<SharedCameraScreen> createState() => _SharedCameraScreenState();
}

class _SharedCameraScreenState extends State<SharedCameraScreen>
    with WidgetsBindingObserver {
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

  CameraCapturePolicy get _policy => widget.policy;

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
          '[공용 카메라 방향 잠금] target=camera '
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
      developer.log('[공용 카메라] target=camera result=SUCCESS');
    } catch (error, stackTrace) {
      if (nextController != null) await nextController.dispose();
      if (!mounted || generation != _cameraGeneration) return;
      developer.log(
        '[공용 카메라] target=camera '
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
      final maxBytes = _policy.maxCaptureBytes;
      if (maxBytes != null) {
        final sizeBytes = await File(file.path).length();
        if (sizeBytes > maxBytes) {
          developer.log(
            '[공용 카메라 촬영] target=camera result=FAIL reason=file_too_large',
          );
          unawaited(_deleteFileQuietly(file.path));
          if (mounted) {
            final copy = _policy.captureTooLargeCopy;
            await AppAlert.show(
              context,
              title: copy?.title ?? '사진 용량이 너무 큽니다',
              message: copy?.message ?? '5MB 이하로 촬영하거나 갤러리에서 다른 사진을 선택해 주세요.',
            );
          }
          return;
        }
      }
      developer.log('[공용 카메라 촬영] target=camera result=SUCCESS');
      if (mounted) Navigator.of(context).pop(file.path);
    } catch (error, stackTrace) {
      developer.log(
        '[공용 카메라 촬영] target=camera '
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
    String? resultPath;
    String? partialCopyPath;
    try {
      final picked = await pickImageFromGallery(
        imageQuality: _policy.galleryImageQuality,
        maxWidth: _policy.galleryMaxWidth,
      );
      if (picked == null) return;
      developer.log('[공용 카메라 갤러리 선택] target=image_picker result=SUCCESS');
      if (!_policy.copyGalleryPickToTemp) {
        resultPath = picked;
      } else {
        final temporaryDirectory = await getTemporaryDirectory();
        final extension = path.extension(picked).isEmpty
            ? '.jpg'
            : path.extension(picked);
        final prefix = _policy.tempFilePrefix ?? 'shared_camera_gallery_';
        final copyPath = path.join(
          temporaryDirectory.path,
          '$prefix${DateTime.now().microsecondsSinceEpoch}$extension',
        );
        partialCopyPath = copyPath;
        await File(picked).copy(copyPath);
        resultPath = copyPath;
      }
      if (mounted) Navigator.of(context).pop(resultPath);
    } catch (error, stackTrace) {
      developer.log(
        '[공용 카메라 갤러리 선택] target=image_picker '
        'result=FAIL reason=gallery_image_pick_error',
        error: error,
        stackTrace: stackTrace,
      );
      if (resultPath == null && partialCopyPath != null) {
        unawaited(_deleteFileQuietly(partialCopyPath));
      }
      if (mounted) {
        await AppAlert.show(
          context,
          title: '사진을 불러오지 못했습니다',
          message: '잠시 후 다시 시도해 주세요.',
        );
      }
    } finally {
      // 성공해서 화면이 닫히는 중이면(resultPath != null) 이미 못 쓰게 될
      // 카메라를 다시 초기화할 필요가 없다 — 선택 중 백그라운드 전환으로
      // 해제된 카메라를 여기서 재획득하면 화면 전환과 리소스 재획득이
      // 경합한다.
      if (mounted && resultPath == null) {
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
              _buildPreview(controller)
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
            if (_policy.guideOverlayBuilder case final builder?)
              Positioned.fill(child: builder(context)),
            if (_policy.hintText case final hint?)
              Positioned(
                left: 24,
                right: 24,
                bottom: 124,
                child: Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.surface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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
                        color: AppColors.accentFill,
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

  Widget _buildPreview(CameraController controller) {
    switch (_policy.previewMode) {
      case CameraPreviewMode.direct:
        return Center(child: CameraPreview(controller));
      case CameraPreviewMode.rotatedAspectRatio:
        // CameraPreview는 Android에서 lockedCaptureOrientation을 읽어
        // 프리뷰 자체를 RotatedBox로 돌린다. 앱 화면은 세로 고정이므로
        // 플랫폼 프리뷰를 세로 비율로 직접 표시해, 촬영 방향과 아이콘만
        // 기기 자세를 따르고 사용자가 보는 프리뷰는 움직이지 않게 한다.
        return Center(
          child: AspectRatio(
            aspectRatio: 1 / controller.value.aspectRatio,
            child: controller.buildPreview(),
          ),
        );
    }
  }
}

Future<void> _deleteFileQuietly(String filePath) async {
  try {
    await File(filePath).delete();
  } catch (_) {
    // 임시 촬영 파일 정리 실패는 사용자 흐름에 영향을 주지 않는다.
  }
}
