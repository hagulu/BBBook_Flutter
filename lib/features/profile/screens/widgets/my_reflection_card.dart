import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/preview_text.dart';
import '../../../../shared/widgets/community_content.dart';
import '../../../discussion/utils/discussion_date.dart';
import '../../models/my_reflection_summary.dart';
import 'my_content_card_layout.dart';

/// "내가 작성한 독후감" 목록 카드(`my-content-screens.md` §2-1).
class MyReflectionCard extends StatelessWidget {
  const MyReflectionCard({
    super.key,
    required this.reflection,
    required this.onTap,
  });

  final MyReflectionSummary reflection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CommunityContentCard(
      onTap: onTap,
      child: MyContentCardLayout(
        book: reflection.book,
        dateLabel: formatRelativeDiscussionDateTime(reflection.createdAt),
        title: Text(
          reflection.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.bold,
            color: AppColors.of(context).textStrong,
          ),
        ),
        content: Text(
          flattenPreviewText(reflection.previewText) ?? '',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.of(context).textBody,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
