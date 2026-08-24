import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/storage/local_image_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../services/reflection_image_store.dart';

/// 독후감 이미지의 Quill embed 렌더링과 크기/삭제 메뉴를 담당한다.
///
/// 너비는 Quill의 `width` attribute에 픽셀 값으로 저장해 기존 웹 Tiptap
/// 변환 포맷과 동일한 필드를 유지한다.
///
/// 본문의 이미지 출처는 두 종류다 — 서버 URL과, 아직 업로드되지 않은 로컬
/// 상대 경로(`reflection_images/...`). 서버 URL은 [localImagePaths] 매칭에
/// 로컬 사본이 있으면 그 파일을 먼저 쓴다(오프라인 조회·네트워크 절약).
class ReflectionImageEmbedBuilder extends EmbedBuilder {
  const ReflectionImageEmbedBuilder({this.localImagePaths = const {}});

  /// 서버 이미지 URL → 로컬 사본 상대 경로(`reflection_image_local`).
  final Map<String, String> localImagePaths;

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
        final savedWidth = _readSavedWidth(embedContext);
        final imageWidth = (savedWidth ?? bodyWidth).clamp(1.0, bodyWidth);
        final image = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _buildImage(source, imageWidth),
        );

        return Align(
          alignment: Alignment.center,
          child: embedContext.readOnly
              ? image
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

  double? _readSavedWidth(EmbedContext embedContext) {
    final value =
        embedContext.node.style.attributes[Attribute.width.key]?.value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll('px', ''));
    return null;
  }

  Future<void> _showImageMenu(
    BuildContext context, {
    required QuillController controller,
    required int offset,
    required double bodyWidth,
    required double imageWidth,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      requestFocus: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => RecordDialogShell(
        title: '이미지 크기',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ImageMenuItem(
              icon: PhosphorIconsRegular.arrowsIn,
              label: '작게',
              description: '본문 폭의 약 50%',
              selected: _isSelected(imageWidth, bodyWidth, 0.5),
              onTap: () => _resize(
                sheetContext,
                controller: controller,
                offset: offset,
                width: bodyWidth * 0.5,
              ),
            ),
            _ImageMenuItem(
              icon: PhosphorIconsRegular.arrowsHorizontal,
              label: '보통',
              description: '본문 폭의 약 75%',
              selected: _isSelected(imageWidth, bodyWidth, 0.75),
              onTap: () => _resize(
                sheetContext,
                controller: controller,
                offset: offset,
                width: bodyWidth * 0.75,
              ),
            ),
            _ImageMenuItem(
              icon: PhosphorIconsRegular.arrowsOut,
              label: '크게',
              description: '본문 폭의 100%',
              selected: _isSelected(imageWidth, bodyWidth, 1),
              onTap: () => _resize(
                sheetContext,
                controller: controller,
                offset: offset,
                width: bodyWidth,
              ),
            ),
            const Divider(color: AppColors.border),
            _ImageMenuItem(
              icon: PhosphorIconsRegular.trash,
              label: '삭제',
              foregroundColor: AppColors.error,
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller
                  ..skipRequestKeyboard = true
                  ..replaceText(
                    offset,
                    1,
                    '',
                    TextSelection.collapsed(offset: offset),
                  );
              },
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
    required double width,
  }) {
    Navigator.of(sheetContext).pop();
    controller
      ..skipRequestKeyboard = true
      ..formatText(offset, 1, WidthAttribute(width.toStringAsFixed(1)));
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 21, color: foregroundColor),
      title: Text(label, style: TextStyle(color: foregroundColor)),
      subtitle: description == null
          ? null
          : Text(
              description!,
              style: const TextStyle(color: AppColors.textMuted),
            ),
      trailing: selected
          ? const Icon(
              PhosphorIconsRegular.check,
              size: 18,
              color: AppColors.accentForeground,
            )
          : null,
      onTap: onTap,
    );
  }
}
