import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/discussion_topic.dart';
import '../../utils/discussion_poll.dart';

/// 선택지 결과 바 목록. 선택지 토론에서만 그린다.
///
/// 닫힌 토론([interactive]가 false)에서는 클릭할 수 없는 결과 표시 전용으로
/// 렌더링된다. 선택 가능한 상태에서 행을 누르면 해당 선택지가 강조되고, 화면
/// 쪽에서 바로 아래에 답변 작성 폼을 연다.
class DiscussionPoll extends StatelessWidget {
  const DiscussionPoll({
    super.key,
    required this.detail,
    required this.interactive,
    required this.selectedOptionId,
    required this.isOtherSelected,
    required this.onSelect,
  });

  final DiscussionTopicDetail detail;
  final bool interactive;

  /// 선택된 선택지 ID. "기타"를 고른 경우 null이면서 [isOtherSelected]가 true다.
  final int? selectedOptionId;
  final bool isOtherSelected;

  /// [optionId]가 null이면 "기타"를 선택한 것이다.
  final void Function(int? optionId) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '의견 선택',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    interactive ? '선택하면 바로 의견을 작성할 수 있어요.' : '마감된 토론의 결과입니다.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '의견 ${detail.totalVoteCount}개',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < detail.options.length; i++) ...[
          _PollRow(
            label: detail.options[i].content,
            percentage: detail.options[i].votePercentage,
            color: discussionOptionColorAt(i),
            isTop: _isTopPercentage(detail.options[i].votePercentage),
            isSelected: selectedOptionId == detail.options[i].id,
            onTap: interactive ? () => onSelect(detail.options[i].id) : null,
          ),
          const SizedBox(height: 8),
        ],
        _PollRow(
          label: '기타',
          percentage: detail.otherVotePercentage,
          color: discussionOtherOptionColor,
          isTop: _isTopPercentage(detail.otherVotePercentage),
          isSelected: isOtherSelected,
          onTap: interactive ? () => onSelect(null) : null,
        ),
      ],
    );
  }

  /// 가장 높은 비율은 굵게 강조한다(동률이면 모두 강조). 투표가 하나도 없으면
  /// 모든 값이 0이므로 강조하지 않는다.
  bool _isTopPercentage(double value) {
    if (detail.totalVoteCount == 0) return false;
    final max = [
      ...detail.options.map((o) => o.votePercentage),
      detail.otherVotePercentage,
    ].reduce((a, b) => a > b ? a : b);
    return value >= max;
  }
}

class _PollRow extends StatelessWidget {
  const _PollRow({
    required this.label,
    required this.percentage,
    required this.color,
    required this.isTop,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final double percentage;
  final Color color;
  final bool isTop;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = (percentage / 100).clamp(0.0, 1.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : AppColors.border,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // 게이지: 비율만큼 선택지 색의 옅은 톤으로 채운다.
              FractionallySizedBox(
                widthFactor: ratio,
                heightFactor: 1,
                child: ColoredBox(color: color.withValues(alpha: 0.18)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isTop
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: AppColors.textStrong,
                        ),
                      ),
                    ),
                    if (isSelected) ...[
                      Icon(PhosphorIconsFill.checkCircle, size: 16, color: color),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      formatVotePercentage(percentage),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isTop ? FontWeight.bold : FontWeight.w500,
                        color: AppColors.textStrong,
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
  }
}

/// 답변에 붙는 선택 배너(어떤 선택지로 남긴 의견인지 표시).
class DiscussionVoteBanner extends StatelessWidget {
  const DiscussionVoteBanner({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsFill.checkCircle, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
