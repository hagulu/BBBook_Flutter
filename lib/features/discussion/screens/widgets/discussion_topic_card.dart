import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/discussion_topic.dart';
import '../../utils/discussion_date.dart';
import 'discussion_common.dart';

/// 토론 목록의 카드 한 장.
///
/// 숨김 처리된 주제는 제목·본문 대신 안내 문구만 노출하고, 스포일러 주제는
/// 본문 미리보기를 대체 문구로 바꾼다.
class DiscussionTopicCard extends StatelessWidget {
  const DiscussionTopicCard({
    super.key,
    required this.topic,
    required this.onTap,
  });

  final DiscussionTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: topic.isHidden
              ? const Text(
                  '숨김 처리된 토론입니다.',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (topic.isClosed || topic.isSpoiler) ...[
                      Wrap(
                        spacing: 6,
                        children: [
                          if (topic.isClosed) const DiscussionBadge.closed(),
                          if (topic.isSpoiler) const DiscussionBadge.spoiler(),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      topic.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      topic.isSpoiler
                          ? '스포일러가 포함된 토론입니다'
                          : (topic.content ?? ''),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DiscussionAuthorRow(
                      user: topic.user,
                      createdAt: topic.createdAt,
                      showTime: false,
                      avatarRadius: 12,
                      trailing: const Icon(
                        PhosphorIconsRegular.caretRight,
                        size: 16,
                        color: AppColors.controlInactive,
                      ),
                    ),
                    if (_metaItems.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          for (final item in _metaItems)
                            _MetaChip(icon: item.$1, label: item.$2),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  /// 공감 수/마감일은 값이 있을 때만 노출한다(답변 수는 목록 응답 규격에 없어
  /// 표시하지 않는다).
  List<(IconData, String)> get _metaItems => [
    if (topic.likeCount > 0)
      (PhosphorIconsRegular.heart, '공감 ${topic.likeCount}'),
    if (topic.closesAt != null && !topic.isClosed)
      (
        PhosphorIconsRegular.calendarBlank,
        '${formatDiscussionDate(topic.closesAt!)} 마감',
      ),
  ];
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.controlInactive),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
