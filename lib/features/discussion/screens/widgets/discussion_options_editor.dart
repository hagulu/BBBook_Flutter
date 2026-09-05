import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../utils/discussion_poll.dart';

/// 선택지 입력 UI. 순서는 항상 작성한 순서대로 고정이며 바꿀 수 없다.
///
/// [lockedCount]만큼의 앞쪽 선택지는 이미 저장된 항목이라 수정·삭제가
/// 불가능하다(수정 화면의 append-only 제약). 마지막에는 사용자가 만들 수 없는
/// "기타"가 자동 제공 항목으로 항상 붙는다.
class DiscussionOptionsEditor extends StatelessWidget {
  const DiscussionOptionsEditor({
    super.key,
    required this.controllers,
    required this.lockedCount,
    required this.enabled,
    required this.onRemove,
    this.autofocusIndex,
    this.autofocusNode,
  });

  final List<TextEditingController> controllers;
  final int lockedCount;
  final bool enabled;
  final void Function(int index) onRemove;

  /// 이 인덱스의 선택지 입력창에 자동 포커스를 준다(방금 추가한 항목이라
  /// 키보드가 내려갔다 다시 올라오는 깜빡임 없이 바로 이어서 입력할 수 있게).
  final int? autofocusIndex;

  /// [autofocusIndex] 행에 붙는 포커스 노드. `autofocus`는 시트 안에 이미
  /// 포커스를 가진 다른 입력창이 있으면 동작하지 않으므로("+"로 추가한
  /// 경우), 호출부가 이 노드에 명시적으로 `requestFocus()`를 걸어 보정한다.
  final FocusNode? autofocusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < controllers.length; i++) ...[
          _OptionRow(
            // 컨트롤러 identity를 key로 써서, 목록 중간 항목을 삭제해도
            // Flutter가 엘리먼트를 위치 기준으로 잘못 재사용하지 않게 한다
            // (재사용되면 이전 행의 포커스·커서 오버레이가 다른 컨트롤러의
            // 입력창에 그대로 남는 버그가 생긴다).
            key: ValueKey(controllers[i]),
            controller: controllers[i],
            color: discussionOptionColorAt(i),
            index: i,
            isLocked: i < lockedCount,
            enabled: enabled,
            autofocus: i == autofocusIndex,
            focusNode: i == autofocusIndex ? autofocusNode : null,
            onRemove: () => onRemove(i),
          ),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
              const SizedBox(width: 12),
              const Text(
                '자동 제공',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.controller,
    required this.color,
    required this.index,
    required this.isLocked,
    required this.enabled,
    required this.onRemove,
    this.autofocus = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final Color color;
  final int index;
  final bool isLocked;
  final bool enabled;
  final VoidCallback onRemove;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // 선택지 색을 옅은 배경으로(선택지 결과 바의 % 게이지와 같은 톤).
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled && !isLocked,
              autofocus: autofocus,
              focusNode: focusNode,
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
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
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
              padding: EdgeInsets.only(right: 10),
              child: Icon(
                PhosphorIconsRegular.lock,
                size: 16,
                color: AppColors.controlInactive,
              ),
            )
          else
            _IconAction(
              icon: PhosphorIconsRegular.trash,
              tooltip: '선택지 ${index + 1} 삭제',
              onPressed: enabled ? onRemove : null,
            ),
        ],
      ),
    );
  }
}

/// 삭제 버튼. 아이콘은 작게 두되 터치 영역은 [kMinInteractiveDimension]
/// (48dp)을 그대로 쓴다. 스크린리더와 롱프레스 힌트를 위해 [tooltip]도
/// 함께 지정한다.
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
        color: onPressed == null ? AppColors.border : AppColors.controlInactive,
      ),
      onPressed: onPressed,
    );
  }
}
