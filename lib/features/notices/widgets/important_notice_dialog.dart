import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/record_dialog_shell.dart';
import '../models/notice_detail.dart';
import '../providers/notices_providers.dart';

/// 노출 대상 중요 공지가 있으면 바텀시트를 한 번 띄운다. 여러 건이면 시트 안에서
/// 좌우로 넘겨 본다. 조회·저장 실패는 조용히 무시한다(공지는 부가 안내라 앱
/// 사용을 막지 않는다).
Future<void> showImportantNoticeIfNeeded(
  BuildContext context,
  WidgetRef ref,
) async {
  final List<NoticeDetail> notices;
  try {
    notices = await ref.read(importantNoticesToShowProvider.future);
  } catch (_) {
    return;
  }
  if (notices.isEmpty || !context.mounted) return;

  final store = ref.read(importantNoticeDismissedStoreProvider);
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ImportantNoticeSheet(
      notices: notices,
      onDismissForever: (id) => store.add(id),
    ),
  );
}

/// 본문이 짧아도 확보하는 최소 높이(스크롤 영역).
const double _minContentHeight = 160;

class _ImportantNoticeSheet extends StatefulWidget {
  const _ImportantNoticeSheet({
    required this.notices,
    required this.onDismissForever,
  });

  final List<NoticeDetail> notices;
  final void Function(int id) onDismissForever;

  @override
  State<_ImportantNoticeSheet> createState() => _ImportantNoticeSheetState();
}

class _ImportantNoticeSheetState extends State<_ImportantNoticeSheet> {
  late final List<NoticeDetail> _notices = [...widget.notices];
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 지금 보고 있는 공지만 그만 보기 처리하고 목록에서 뺀다. 마지막 한 건이면 닫는다.
  void _dismissCurrentForever() {
    widget.onDismissForever(_notices[_index].id);
    if (_notices.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    final next = _index == _notices.length - 1 ? _index - 1 : _index;
    setState(() {
      _notices.removeAt(_index);
      _index = next;
    });
    if (_controller.hasClients) _controller.jumpToPage(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // 시트 상단이 앱바 하단 근처까지만 오도록 시트 전체 높이를 제한한다. 본문은
    // 제목·버튼을 뺀 남은 공간(Flexible)만 쓰므로 큰 글씨·긴 제목에서도 버튼이
    // 잘리지 않는다.
    final media = MediaQuery.of(context);
    final maxSheetHeight =
        media.size.height -
        media.viewPadding.top -
        kToolbarHeight -
        media.viewInsets.bottom -
        media.viewPadding.bottom -
        RecordDialogMetrics.topPadding -
        RecordDialogMetrics.bottomPadding;
    return RecordDialogSurface(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RecordDialogHandle(),
            const SizedBox(height: RecordDialogMetrics.handleToHeader),
            Row(
              children: [
                Icon(
                  PhosphorIconsFill.megaphone,
                  size: 20,
                  color: colors.accentForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _notices[_index].title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colors.textStrong,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: RecordDialogMetrics.headerToContent),
            Flexible(
              child: _NoticePager(
                notices: _notices,
                controller: _controller,
                index: _index,
                onChanged: (value) => setState(() => _index = value),
              ),
            ),
            const SizedBox(height: RecordDialogMetrics.contentToButtons),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: '그만 보기',
                    neutral: true,
                    onPressed: _dismissCurrentForever,
                  ),
                ),
                const SizedBox(width: RecordDialogMetrics.buttonSpacing),
                Expanded(
                  child: _SheetButton(
                    label: '확인',
                    neutral: false,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.neutral,
    required this.onPressed,
  });

  final String label;
  final bool neutral;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: neutral ? colors.surfaceSubtle : colors.accentFill,
        foregroundColor: neutral ? colors.textBody : colors.textStrong,
        elevation: 0,
        minimumSize: const Size.fromHeight(RecordDialogMetrics.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            RecordDialogMetrics.controlRadius,
          ),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      child: Text(label),
    );
  }
}

/// 공지 본문을 좌우로 스와이프해 넘기는 페이저(한 건이면 넘김 없이 본문만).
/// 높이는 현재 공지에 맞춰 애니메이션으로 바뀌고 상한을 넘으면 페이지 안에서만 세로 스크롤한다.
class _NoticePager extends StatelessWidget {
  const _NoticePager({
    required this.notices,
    required this.controller,
    required this.index,
    required this.onChanged,
  });

  final List<NoticeDetail> notices;
  final PageController controller;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textStyle = TextStyle(
      fontSize: 15,
      color: colors.textBody,
      height: 1.4,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 현재 보고 있는 공지의 본문 높이에 맞춰 부드럽게 늘었다 줄었다 한다.
        // 남은 공간이 최소 높이보다 작으면 그 공간까지만 쓴다(Flexible).
        Flexible(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final painter = TextPainter(
                text: TextSpan(text: notices[index].content, style: textStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: constraints.maxWidth);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                width: double.infinity,
                height: max(painter.height, _minContentHeight),
                child: PageView.builder(
                  controller: controller,
                  itemCount: notices.length,
                  onPageChanged: onChanged,
                  itemBuilder: (_, i) => SingleChildScrollView(
                    child: Text(notices[i].content, style: textStyle),
                  ),
                ),
              );
            },
          ),
        ),
        if (notices.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < notices.length; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == index
                        ? colors.accentGraphic
                        : colors.controlInactive,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
