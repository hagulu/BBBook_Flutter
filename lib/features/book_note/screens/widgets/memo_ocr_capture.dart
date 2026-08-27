import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/image/screens/shared_camera_screen.dart';
import '../../../../shared/image/screens/shared_image_editor_screen.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../services/book_note_memo_ocr_service.dart';

/// 발췌 OCR용 촬영 정책 — 문장을 수평으로 맞출 가이드를 겹쳐 그리고,
/// 갤러리 선택은 인식률을 위해 압축하지 않은 원본을 그대로 받아 분석이
/// 끝날 때까지 살아있을 임시 경로로 복사해 둔다.
const _memoOcrCapturePolicy = CameraCapturePolicy(
  guideOverlayBuilder: _buildOcrGuideOverlay,
  hintText: '문장이 가이드선과 수평이 되도록 맞춰주세요.',
  copyGalleryPickToTemp: true,
  tempFilePrefix: 'memo_ocr_gallery_',
);

Widget _buildOcrGuideOverlay(BuildContext context) {
  return const Padding(
    padding: EdgeInsets.symmetric(horizontal: 24),
    child: Center(child: _HorizontalGuide()),
  );
}

class _HorizontalGuide extends StatelessWidget {
  const _HorizontalGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      decoration: BoxDecoration(
        color: AppColors.accentFill,
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

/// 카메라 촬영부터 단어 드래그 선택까지 진행하고 발췌문을 반환한다.
Future<String?> captureMemoQuoteWithOcr(BuildContext context) async {
  final capturedPath = await showSharedCameraScreen(
    context,
    policy: _memoOcrCapturePolicy,
  );
  if (capturedPath == null) return null;
  if (!context.mounted) {
    await _deleteCapturedFile(capturedPath);
    return null;
  }

  // 크롭/회전만 지원한다 — 인식 대상 문장을 텍스트/그리기로 가릴 이유가
  // 없다. 편집을 건너뛰면(취소) 촬영/선택 원본을 그대로 분석한다.
  final editedPath = await openSharedImageEditor(
    context,
    imagePath: capturedPath,
    profile: SharedImageEditorProfile.cropRotateOnly,
  );
  final analyzedPath = editedPath ?? capturedPath;
  if (editedPath != null) await _deleteCapturedFile(capturedPath);
  if (!context.mounted) {
    await _deleteCapturedFile(analyzedPath);
    return null;
  }

  try {
    BookNoteMemoOcrAnalysis? analysis;
    AppLoading.show(context);
    try {
      analysis = await const BookNoteMemoOcrService().analyzeImage(analyzedPath);
    } catch (_) {
      analysis = null;
    } finally {
      AppLoading.hide();
    }

    if (!context.mounted) return null;
    if (analysis == null) {
      await AppAlert.show(
        context,
        title: '글자를 인식하지 못했습니다',
        message: '문장이 선명하게 보이도록 다시 촬영해 주세요.',
      );
      return null;
    }
    if (analysis.words.isEmpty) {
      await AppAlert.show(
        context,
        title: '인식된 글자가 없습니다',
        message: '글자가 포함되도록 다시 촬영해 주세요.',
      );
      return null;
    }

    final selectedText = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MemoOcrSelectionScreen(
          imagePath: analyzedPath,
          analysis: analysis!,
        ),
      ),
    );
    return selectedText;
  } finally {
    await _deleteCapturedFile(analyzedPath);
  }
}

Future<void> _deleteCapturedFile(String path) async {
  try {
    await File(path).delete();
  } catch (_) {
    // camera 플러그인의 촬영 결과는 임시 파일이므로 정리에 실패해도 OCR 흐름은 유지한다.
  }
}

class _MemoOcrSelectionScreen extends StatefulWidget {
  const _MemoOcrSelectionScreen({
    required this.imagePath,
    required this.analysis,
  });

  final String imagePath;
  final BookNoteMemoOcrAnalysis analysis;

  @override
  State<_MemoOcrSelectionScreen> createState() =>
      _MemoOcrSelectionScreenState();
}

class _MemoOcrSelectionScreenState extends State<_MemoOcrSelectionScreen> {
  Set<int> _selectedIndexes = <int>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mediaBackdrop,
      appBar: AppBar(
        backgroundColor: AppColors.mediaBackdrop,
        foregroundColor: AppColors.surface,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '닫기',
          icon: const Icon(PhosphorIconsRegular.x),
        ),
        title: const Text(
          '발췌 문장 선택',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: _selectedIndexes.isEmpty
                ? null
                : () => setState(() => _selectedIndexes = <int>{}),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.surface,
              disabledForegroundColor: AppColors.surface.withValues(
                alpha: 0.4,
              ),
            ),
            child: const Text('선택 취소'),
          ),
          TextButton(
            onPressed: _selectedIndexes.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selectedText()),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.surface,
              disabledForegroundColor: AppColors.surface.withValues(
                alpha: 0.4,
              ),
            ),
            child: const Text(
              '완료',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _OcrPhotoCanvas(
              imagePath: widget.imagePath,
              analysis: widget.analysis,
              selectedIndexes: _selectedIndexes,
              onSelectionChanged: (indexes) {
                setState(() => _selectedIndexes = indexes);
              },
            ),
          ),
          Container(
            width: double.infinity,
            color: AppColors.mediaBackdrop,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _selectedIndexes.isEmpty
                        ? '발췌할 단어를 드래그해 주세요.'
                        : '${_selectedIndexes.length}개 단어가 선택되었습니다.',
                    style: TextStyle(
                      color: AppColors.surface.withValues(alpha: 0.84),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _selectedText() {
    final selected = _selectedIndexes.toList()..sort();
    final lines = <int, List<BookNoteMemoOcrWord>>{};
    for (final index in selected) {
      final word = widget.analysis.words[index];
      lines.putIfAbsent(word.lineOrder, () => <BookNoteMemoOcrWord>[]).add(word);
    }
    final orderedLines = lines.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return orderedLines
        .map((entry) {
          entry.value.sort(
            (left, right) => left.wordOrder.compareTo(right.wordOrder),
          );
          return entry.value.map((word) => word.text).join(' ');
        })
        .join('\n');
  }
}

class _OcrPhotoCanvas extends StatefulWidget {
  const _OcrPhotoCanvas({
    required this.imagePath,
    required this.analysis,
    required this.selectedIndexes,
    required this.onSelectionChanged,
  });

  final String imagePath;
  final BookNoteMemoOcrAnalysis analysis;
  final Set<int> selectedIndexes;
  final ValueChanged<Set<int>> onSelectionChanged;

  @override
  State<_OcrPhotoCanvas> createState() => _OcrPhotoCanvasState();
}

class _OcrPhotoCanvasState extends State<_OcrPhotoCanvas> {
  final TransformationController _transformationController =
      TransformationController();
  Offset? _lastSelectionPoint;
  Offset? _lastMultiTouchFocalPoint;
  double _lastGestureScale = 1;
  bool _gestureUsedMultiplePointers = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.mediaBackdrop,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final fitScale = math.min(
            viewportSize.width / widget.analysis.imageSize.width,
            viewportSize.height / widget.analysis.imageSize.height,
          );
          final displaySize = Size(
            widget.analysis.imageSize.width * fitScale,
            widget.analysis.imageSize.height * fitScale,
          );
          final imageOrigin = Offset(
            (viewportSize.width - displaySize.width) / 2,
            (viewportSize.height - displaySize.height) / 2,
          );

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _handleGestureStart,
            onScaleUpdate: (details) => _handleGestureUpdate(
              details,
              imageOrigin: imageOrigin,
              fitScale: fitScale,
            ),
            onScaleEnd: (_) => _handleGestureEnd(),
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _transformationController,
                builder: (context, child) => Transform(
                  transform: _transformationController.value,
                  alignment: Alignment.topLeft,
                  child: child,
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: imageOrigin.dx,
                      top: imageOrigin.dy,
                      width: displaySize.width,
                      height: displaySize.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(widget.imagePath),
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.high,
                          ),
                          CustomPaint(
                            painter: _OcrWordSelectionPainter(
                              words: widget.analysis.words,
                              selectedIndexes: widget.selectedIndexes,
                              fitScale: fitScale,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleGestureStart(ScaleStartDetails details) {
    _lastSelectionPoint = null;
    _lastMultiTouchFocalPoint = null;
    _lastGestureScale = 1;
    _gestureUsedMultiplePointers = details.pointerCount > 1;
  }

  void _handleGestureUpdate(
    ScaleUpdateDetails details, {
    required Offset imageOrigin,
    required double fitScale,
  }) {
    if (details.pointerCount > 1) {
      _gestureUsedMultiplePointers = true;
      _updateTransformation(details);
      return;
    }
    if (_gestureUsedMultiplePointers) return;
    _selectAt(details.localFocalPoint, imageOrigin, fitScale);
  }

  void _handleGestureEnd() {
    _lastSelectionPoint = null;
    _lastMultiTouchFocalPoint = null;
    _lastGestureScale = 1;
    _gestureUsedMultiplePointers = false;
  }

  void _updateTransformation(ScaleUpdateDetails details) {
    final focalPoint = details.localFocalPoint;
    final previousFocalPoint = _lastMultiTouchFocalPoint;
    if (previousFocalPoint == null) {
      _lastMultiTouchFocalPoint = focalPoint;
      _lastGestureScale = details.scale;
      return;
    }

    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final rawScale = _lastGestureScale == 0
        ? 1.0
        : details.scale / _lastGestureScale;
    final targetScale = (currentScale * rawScale).clamp(1.0, 5.0);
    final scaleChange = targetScale / currentScale;
    final incremental = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(scaleChange, scaleChange, 1, 1)
      ..translateByDouble(-previousFocalPoint.dx, -previousFocalPoint.dy, 0, 1);
    _transformationController.value = incremental * currentMatrix;
    _lastMultiTouchFocalPoint = focalPoint;
    _lastGestureScale = details.scale;
  }

  void _selectAt(Offset viewportPoint, Offset imageOrigin, double fitScale) {
    final scenePoint = _transformationController.toScene(viewportPoint);
    final sourcePoint = Offset(
      (scenePoint.dx - imageOrigin.dx) / fitScale,
      (scenePoint.dy - imageOrigin.dy) / fitScale,
    );
    final previousPoint = _lastSelectionPoint;
    _lastSelectionPoint = sourcePoint;

    final selected = Set<int>.of(widget.selectedIndexes);
    final step = math.max(2.0, 8 / fitScale);
    final distance = previousPoint == null
        ? 0.0
        : (sourcePoint - previousPoint).distance;
    final sampleCount = math.max(1, (distance / step).ceil());
    for (var sample = 0; sample <= sampleCount; sample++) {
      final ratio = sample / sampleCount;
      final point = previousPoint == null
          ? sourcePoint
          : Offset.lerp(previousPoint, sourcePoint, ratio)!;
      for (var index = 0; index < widget.analysis.words.length; index++) {
        if (widget.analysis.words[index].boundingBox
            .inflate(6)
            .contains(point)) {
          selected.add(index);
        }
      }
    }
    if (selected.length != widget.selectedIndexes.length) {
      widget.onSelectionChanged(selected);
    }
  }
}

class _OcrWordSelectionPainter extends CustomPainter {
  const _OcrWordSelectionPainter({
    required this.words,
    required this.selectedIndexes,
    required this.fitScale,
  });

  final List<BookNoteMemoOcrWord> words;
  final Set<int> selectedIndexes;
  final double fitScale;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = AppColors.highlightGoldSurface.withValues(alpha: 0.58);
    for (final index in selectedIndexes) {
      final sourceRect = words[index].boundingBox;
      final rect = Rect.fromLTRB(
        sourceRect.left * fitScale,
        sourceRect.top * fitScale,
        sourceRect.right * fitScale,
        sourceRect.bottom * fitScale,
      );
      final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rounded, fill);
    }
  }

  @override
  bool shouldRepaint(_OcrWordSelectionPainter oldDelegate) =>
      oldDelegate.selectedIndexes != selectedIndexes ||
      oldDelegate.words != words ||
      oldDelegate.fitScale != fitScale;
}
