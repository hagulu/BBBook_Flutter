import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../utils/discussion_poll.dart';

/// 선택지 입력 UI.
///
/// [lockedCount]만큼의 앞쪽 선택지는 이미 저장된 항목이라 수정·삭제·순서 변경이
/// 불가능하다(수정 화면의 append-only 제약). 마지막에는 사용자가 만들 수 없는
/// "기타"가 자동 제공 항목으로 항상 붙는다.
class DiscussionOptionsEditor extends StatelessWidget {
  const DiscussionOptionsEditor({
    super.key,
    required this.controllers,
    required this.lockedCount,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    required this.onMove,
  });

  final List<TextEditingController> controllers;
  final int lockedCount;
  final bool enabled;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  /// [index]의 선택지를 [delta]만큼(-1 위 / +1 아래) 옮긴다.
  final void Function(int index, int delta) onMove;

  @override
  Widget build(BuildContext context) {
    final canAdd =
        enabled && controllers.length < kMaxDiscussionOptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lockedCount > 0) ...[
          const Text(
            '기존 선택지는 수정하거나 삭제할 수 없습니다. 새 선택지만 추가할 수 있어요.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
        ],
        for (var i = 0; i < controllers.length; i++) ...[
          _OptionRow(
            controller: controllers[i],
            color: discussionOptionColorAt(i),
            index: i,
            isLocked: i < lockedCount,
            enabled: enabled,
            canMoveUp: i > lockedCount,
            canMoveDown: i < controllers.length - 1 && i >= lockedCount,
            onRemove: () => onRemove(i),
            onMove: (delta) => onMove(i, delta),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: discussionOtherOptionColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              '기타',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textStrong,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '자동 제공',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        if (canAdd) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onAdd,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentForeground,
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
            icon: const Icon(PhosphorIconsRegular.plus, size: 15),
            label: Text(
              '선택지 추가 (${controllers.length}/$kMaxDiscussionOptions)',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.controller,
    required this.color,
    required this.index,
    required this.isLocked,
    required this.enabled,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onRemove,
    required this.onMove,
  });

  final TextEditingController controller;
  final Color color;
  final int index;
  final bool isLocked;
  final bool enabled;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onRemove;
  final void Function(int delta) onMove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled && !isLocked,
            maxLength: kMaxDiscussionOptionLength,
            inputFormatters: [
              LengthLimitingTextInputFormatter(kMaxDiscussionOptionLength),
            ],
            style: TextStyle(
              fontSize: 14,
              color: isLocked ? AppColors.textMuted : AppColors.textBody,
            ),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              hintText: '선택지 ${index + 1}',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
        ),
        if (isLocked)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(
              PhosphorIconsRegular.lock,
              size: 16,
              color: AppColors.controlInactive,
            ),
          )
        else ...[
          _IconAction(
            icon: PhosphorIconsRegular.caretUp,
            tooltip: '선택지 ${index + 1} 위로 이동',
            onPressed: enabled && canMoveUp ? () => onMove(-1) : null,
          ),
          _IconAction(
            icon: PhosphorIconsRegular.caretDown,
            tooltip: '선택지 ${index + 1} 아래로 이동',
            onPressed: enabled && canMoveDown ? () => onMove(1) : null,
          ),
          _IconAction(
            icon: PhosphorIconsRegular.trash,
            tooltip: '선택지 ${index + 1} 삭제',
            onPressed: enabled ? onRemove : null,
          ),
        ],
      ],
    );
  }
}

/// 이동/삭제가 나란히 붙어 있어 오조작하기 쉬운 자리라, 아이콘은 작게 두되
/// 터치 영역은 [kMinInteractiveDimension](48dp)을 그대로 쓴다. 스크린리더와
/// 롱프레스 힌트를 위해 [tooltip]도 함께 지정한다.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      icon: Icon(
        icon,
        size: 16,
        color: onPressed == null
            ? AppColors.border
            : AppColors.controlInactive,
      ),
      onPressed: onPressed,
    );
  }
}
