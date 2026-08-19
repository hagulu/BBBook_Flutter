import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_alert.dart';
import '../../../shared/widgets/app_loading.dart';

/// 발췌 OCR용 촬영 화면. 책 문장을 수평으로 맞출 가이드만 제공한다.
class MemoOcrCameraScreen extends StatefulWidget {
  const MemoOcrCameraScreen({super.key});

  @override
  State<MemoOcrCameraScreen> createState() => _MemoOcrCameraScreenState();
}

class _MemoOcrCameraScreenState extends State<MemoOcrCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isLoading = true;
  bool _isTakingPicture = false;
  bool _isPickingImage = false;
  String? _errorMessage;
  int _cameraGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraGeneration++;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_isPickingImage) _initializeCamera();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
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
      setState(() {
        _controller = nextController;
        _isLoading = false;
      });
      developer.log('[메모 발췌 카메라] target=camera result=SUCCESS');
    } catch (error, stackTrace) {
      if (nextController != null) await nextController.dispose();
      if (!mounted || generation != _cameraGeneration) return;
      developer.log(
        '[메모 발췌 카메라] target=camera '
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
      developer.log('[메모 발췌 촬영] target=camera result=SUCCESS');
      if (mounted) Navigator.of(context).pop(file.path);
    } catch (error, stackTrace) {
      developer.log(
        '[메모 발췌 촬영] target=camera '
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
    String? temporaryPath;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final temporaryDirectory = await getTemporaryDirectory();
      final extension = path.extension(picked.path).isEmpty
          ? '.jpg'
          : path.extension(picked.path);
      temporaryPath = path.join(
        temporaryDirectory.path,
        'memo_ocr_gallery_${DateTime.now().microsecondsSinceEpoch}$extension',
      );
      await File(picked.path).copy(temporaryPath);
      developer.log('[메모 발췌 이미지 선택] target=image_picker result=SUCCESS');
      if (mounted) Navigator.of(context).pop(temporaryPath);
    } catch (error, stackTrace) {
      developer.log(
        '[메모 발췌 이미지 선택] target=image_picker '
        'result=FAIL reason=gallery_image_pick_error',
        error: error,
        stackTrace: stackTrace,
      );
      if (temporaryPath != null) {
        try {
          await File(temporaryPath).delete();
        } catch (_) {
          // 생성 도중 실패한 임시 파일 정리 실패는 사용자 흐름에 영향을 주지 않는다.
        }
      }
      if (!mounted) return;
      await AppAlert.show(
        context,
        title: '사진을 불러오지 못했습니다',
        message: '잠시 후 다시 시도해 주세요.',
      );
    } finally {
      if (mounted && temporaryPath == null) {
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
              Center(child: CameraPreview(controller))
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
            const Positioned(
              left: 24,
              right: 24,
              top: 0,
              bottom: 0,
              child: Center(child: _HorizontalGuide()),
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
                  icon: const Icon(PhosphorIconsRegular.x),
                ),
              ),
            ),
            const Positioned(
              left: 24,
              right: 24,
              bottom: 124,
              child: Text(
                '문장이 가이드선과 수평이 되도록 맞춰주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.surface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
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
                  icon: const Icon(PhosphorIconsRegular.imageSquare, size: 24),
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
                    icon: const Icon(PhosphorIconsRegular.camera, size: 28),
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

class _HorizontalGuide extends StatelessWidget {
  const _HorizontalGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      decoration: BoxDecoration(
        color: AppColors.highlightGold,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowStrong,
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
