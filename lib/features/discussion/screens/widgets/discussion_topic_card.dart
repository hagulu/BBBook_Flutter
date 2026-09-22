import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/community_content.dart';
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
    return CommunityContentCard(
      onTap: onTap,
      child: topic.isHidden
          ? Text(
              '숨김 처리된 토론입니다.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.of(context).textMuted,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (topic.isClosed || topic.isSpoiler) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (topic.isClosed) const DiscussionBadge.closed(),
                      if (topic.isSpoiler) const DiscussionBadge.spoiler(),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  topic.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.4,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.bold,
                    color: AppColors.of(context).textStrong,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  topic.isSpoiler ? '스포일러가 포함된 토론입니다' : (topic.content ?? ''),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.of(context).textBody,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                CommunityAuthorRow(
                  nickname: topic.user.nickname,
                  profileImageUrl: topic.user.profileImageUrl,
                  dateLabel: formatRelativeDiscussionDate(topic.createdAt),
                  avatarRadius: 12,
                  trailing: topic.likeCount > 0
                      ? CommunityLikeCount(likeCount: topic.likeCount)
                      : null,
                ),
              ],
            ),
    );
  }
}
