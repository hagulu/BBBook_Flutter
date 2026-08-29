import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/community_content.dart';
import '../../../discussion/utils/discussion_date.dart';
import '../../models/public_reflection.dart';

/// 토론 목록 카드와 같은 표면·간격을 사용하는 공개 독후감 목록 카드.
class PublicReflectionCard extends StatelessWidget {
  const PublicReflectionCard({
    super.key,
    required this.reflection,
    required this.onTap,
  });

  final PublicReflectionSummary reflection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = reflection.title?.trim();
    final preview = reflection.contentText?.trim();

    return CommunityContentCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title == null || title.isEmpty ? '제목 없음' : title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            preview == null || preview.isEmpty ? '내용이 없습니다.' : preview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          CommunityAuthorRow(
            nickname: reflection.user.nickname,
            profileImageUrl: reflection.user.profileImageUrl,
            dateLabel: formatDiscussionDate(reflection.createdAt),
          ),
        ],
      ),
    );
  }
}
