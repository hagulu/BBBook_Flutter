import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/storage/local_image_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/image/widgets/shared_image_viewer.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../services/book_reflection_memo_insert_service.dart';
import '../../services/reflection_image_store.dart';

typedef ReflectionImageDeleteCallback =
    void Function(QuillController controller, int offset);

/// 독후감 이미지의 Quill embed 렌더링과 크기/삭제 메뉴를 담당한다.
///
/// 너비는 Quill의 `width` attribute에 백분율로 저장한다. 기존 데이터의
/// 픽셀 값도 읽을 수 있어 예전에 저장한 독후감과 호환된다.
///
/// 본문의 이미지 출처는 두 종류다 — 서버 URL과, 아직 업로드되지 않은 로컬
/// 상대 경로(`reflection_images/...`). 서버 URL은 [localImagePaths] 매칭에
/// 로컬 사본이 있으면 그 파일을 먼저 쓴다(오프라인 조회·네트워크 절약).
class ReflectionImageEmbedBuilder extends EmbedBuilder {
  const ReflectionImageEmbedBuilder({
    this.localImagePaths = const {},
    this.onDeleteImage,
  });

  /// 서버 이미지 URL → 로컬 사본 상대 경로(`reflection_image_local`).
  final Map<String, String> localImagePaths;
  final ReflectionImageDeleteCallback? onDeleteImage;

  @override
  String get key => BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = embedContext.node.value.data.toString();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bodyWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final savedWidth = _readSavedWidth(embedContext, bodyWidth);
        final imageWidth = (savedWidth ?? bodyWidth).clamp(1.0, bodyWidth);
        final image = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _buildImage(source, imageWidth),
        );

        return Align(
          alignment: Alignment.center,
          child: embedContext.readOnly
              ? Semantics(
                  button: true,
                  label: '이미지 확대 보기',
                  child: GestureDetector(
                    onTap: () => _showFullScreenImage(context, source),
                    child: image,
                  ),
                )
              : GestureDetector(
                  onTap: () => _showImageMenu(
                    context,
                    controller: embedContext.controller,
                    offset: embedContext.node.documentOffset,
                    bodyWidth: bodyWidth,
                    imageWidth: imageWidth,
                  ),
                  child: image,
                ),
        );
      },
    );
  }

  /// 표시 우선순위: 로컬 사본 → 서버 URL. 로컬 파일이 아직 없거나
  /// (매칭 전) 열리지 않으면 서버 URL로 대체한다.
  Widget _buildImage(String source, double imageWidth) {
    final localFile = reflectionImageStore.resolveSync(
      LocalImageStore.isRemote(source) ? localImagePaths[source] : source,
    );
    if (localFile != null && localFile.existsSync()) {
      return Image.file(
        localFile,
        width: imageWidth,
        fit: BoxFit.fitWidth,
        errorBuilder: (_, _, _) => _remoteImage(source, imageWidth),
      );
    }
    return _remoteImage(source, imageWidth);
  }

  Widget _remoteImage(String source, double imageWidth) {
    if (!LocalImageStore.isRemote(source)) {
      return _brokenImage(imageWidth);
    }
    return Image.network(
      source,
      width: imageWidth,
      fit: BoxFit.fitWidth,
      errorBuilder: (_, _, _) => _brokenImage(imageWidth),
    );
  }

  Widget _brokenImage(double imageWidth) {
    return Container(
      width: imageWidth,
      height: 120,
      color: AppColors.surfaceSubtle,
      alignment: Alignment.center,
      child: const Icon(
        PhosphorIconsRegular.imageBroken,
        color: AppColors.textMuted,
      ),
    );
  }

  Widget _buildViewerImage(String source) {
    final localFile = reflectionImageStore.resolveSync(
      LocalImageStore.isRemote(source) ? localImagePaths[source] : source,
    );
    if (localFile != null && localFile.existsSync()) {
      return Image.file(
        localFile,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _viewerRemoteImage(source),
      );
    }
    return _viewerRemoteImage(source);
  }

  Widget _viewerRemoteImage(String source) {
    if (!LocalImageStore.isRemote(source)) {
      return const _ViewerBrokenImage();
    }
    return Image.network(
      source,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const _ViewerBrokenImage(),
    );
  }

  Future<void> _showFullScreenImage(BuildContext context, String source) {
    return showSharedImageViewer(context, image: _buildViewerImage(source));
  }

  double? _readSavedWidth(EmbedContext embedContext, double bodyWidth) {
    final value =
        embedContext.node.style.attributes[Attribute.width.key]?.value;
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value.trim();
      if (normalized.endsWith('%')) {
        final percentage = double.tryParse(
          normalized.substring(0, normalized.length - 1),
        );
        if (percentage != null) return bodyWidth * percentage / 100;
      }
      return double.tryParse(normalized.replaceAll('px', ''));
    }
    return null;
  }

  Future<void> _showImageMenu(
    BuildContext context, {
    required QuillController controller,
    required int offset,
    required double bodyWidth,
    required double imageWidth,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      requestFocus: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => RecordDialogShell(
        title: '이미지 편집',
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ImageMenuItem(
                icon: PhosphorIconsRegular.arrowsIn,
                label: '작게',
                description: '50%',
                selected: _isSelected(imageWidth, bodyWidth, 0.5),
                onTap: () => _resize(
                  sheetContext,
                  controller: controller,
                  offset: offset,
                  ratio: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ImageMenuItem(
                icon: PhosphorIconsRegular.arrowsHorizontal,
                label: '보통',
                description: '75%',
                selected: _isSelected(imageWidth, bodyWidth, 0.75),
                onTap: () => _resize(
                  sheetContext,
                  controller: controller,
                  offset: offset,
                  ratio: 0.75,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ImageMenuItem(
                icon: PhosphorIconsRegular.arrowsOut,
                label: '크게',
                description: '100%',
                selected: _isSelected(imageWidth, bodyWidth, 1),
                onTap: () => _resize(
                  sheetContext,
                  controller: controller,
                  offset: offset,
                  ratio: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ImageMenuItem(
                icon: PhosphorIconsRegular.trash,
                label: '삭제',
                foregroundColor: AppColors.error,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onDeleteImage?.call(controller, offset);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSelected(double width, double bodyWidth, double ratio) {
    return ((width / bodyWidth) - ratio).abs() < 0.08;
  }

  void _resize(
    BuildContext sheetContext, {
    required QuillController controller,
    required int offset,
    required double ratio,
  }) {
    Navigator.of(sheetContext).pop();
    controller.skipRequestKeyboard = true;
    BookReflectionMemoInsertService.setImageWidth(
      controller,
      offset: offset,
      ratio: ratio,
    );
  }
}

class _ViewerBrokenImage extends StatelessWidget {
  const _ViewerBrokenImage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        PhosphorIconsRegular.imageBroken,
        size: 36,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _ImageMenuItem extends StatelessWidget {
  const _ImageMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.description,
    this.selected = false,
    this.foregroundColor = AppColors.textBody,
  });

  final IconData icon;
  final String label;
  final String? description;
  final bool selected;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDestructive = foregroundColor == AppColors.error;
    final iconColor = isDestructive
        ? AppColors.error
        : selected
        ? AppColors.accentForeground
        : AppColors.controlInactive;
    final labelColor = isDestructive
        ? AppColors.error
        : selected
        ? AppColors.accentForeground
        : AppColors.textBody;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 84,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSurface.withValues(alpha: 0.35)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accentForeground : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: iconColor),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(
                  description!,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected
                        ? AppColors.accentForeground
                        : AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
