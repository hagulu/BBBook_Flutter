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
            ? const Text(
                '숨김 처리된 독후감입니다.',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reflection.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textStrong,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reflection.previewText ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
