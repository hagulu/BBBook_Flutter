import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/community_content.dart';
import '../../../discussion/utils/discussion_date.dart';
import '../../models/my_reflection_summary.dart';
import 'my_content_card_layout.dart';

/// "내가 작성한 독후감" 목록 카드(`my-content-screens.md` §2-1).
class MyReflectionCard extends StatelessWidget {
  const MyReflectionCard({super.key, required this.reflection, this.onTap});

  final MyReflectionSummary reflection;

  /// 숨김 처리된 항목은 null(탭 불가).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CommunityContentCard(
      onTap: onTap,
      child: MyContentCardLayout(
        book: reflection.book,
        dateLabel: reflection.isHidden
            ? null
            : formatRelativeDiscussionDateTime(reflection.createdAt),
        content: reflection.isHidden
            ? Text(
                '숨김 처리된 독후감입니다.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.of(context).textMuted,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reflection.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.4,
                      fontWeight: FontWeight.bold,
                      color: AppColors.of(context).textStrong,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    reflection.previewText ?? '',
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.of(context).textBody,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
