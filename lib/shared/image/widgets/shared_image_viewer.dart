import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';

enum SharedImageViewerAction { edit, delete }

/// 공용 이미지 전체화면 뷰어. 확대/축소(핀치)만 제공하는 조회 전용으로도,
/// 하단에 수정/삭제 액션 바를 붙여도 쓸 수 있다.
///
/// 이미지를 어디서 가져올지(로컬 사본/서버 URL 우선순위 등)는 호출부가
/// 이미 완성된 [image] 위젯으로 넘겨준다 — 이 위젯은 표시·확대·액션 UI만
/// 담당한다.
Future<SharedImageViewerAction?> showSharedImageViewer(
  BuildContext context, {
  required Widget image,
  bool showActions = false,
  String editLabel = '수정',
  String deleteLabel = '삭제',
}) {
  return showDialog<SharedImageViewerAction>(
    context: context,
    useRootNavigator: true,
    useSafeArea: false,
    builder: (_) => _SharedImageViewerDialog(
      image: image,
      showActions: showActions,
      editLabel: editLabel,
      deleteLabel: deleteLabel,
    ),
  );
}

class _SharedImageViewerDialog extends StatelessWidget {
  const _SharedImageViewerDialog({
    required this.image,
    required this.showActions,
    required this.editLabel,
    required this.deleteLabel,
  });

  final Widget image;
  final bool showActions;
  final String editLabel;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: AppColors.mediaBackdrop,
      child: Scaffold(
        backgroundColor: AppColors.mediaBackdrop,
        body: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              bottom: false,
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(child: image),
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
                    backgroundColor: AppColors.surface.withValues(alpha: 0.88),
                    foregroundColor: AppColors.textStrong,
                  ),
                  icon: const Icon(PhosphorIconsRegular.x),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: showActions
            ? Material(
                color: AppColors.mediaBackdrop,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(SharedImageViewerAction.edit),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.surface,
                            minimumSize: const Size(96, 48),
                          ),
                          icon: const Icon(PhosphorIconsRegular.pencil, size: 19),
                          label: Text(editLabel),
                        ),
                        const SizedBox(width: 20),
                        TextButton.icon(
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(SharedImageViewerAction.delete),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                            minimumSize: const Size(96, 48),
                          ),
                          icon: const Icon(PhosphorIconsRegular.trash, size: 19),
                          label: Text(deleteLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
