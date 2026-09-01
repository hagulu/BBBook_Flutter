import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/community_content.dart';
import '../../../discussion/utils/discussion_date.dart';
import '../../models/my_discussion_summary.dart';
import 'my_content_card_layout.dart';

/// "내가 작성한 토론" 목록 카드(`my-content-screens.md` §4-1).
class MyDiscussionCard extends StatelessWidget {
  const MyDiscussionCard({super.key, required this.discussion, this.onTap});

  final MyDiscussionSummary discussion;

  /// 숨김 처리된 항목은 null(탭 불가).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CommunityContentCard(
      onTap: onTap,
      child: MyContentCardLayout(
        book: discussion.book,
        dateLabel: discussion.isHidden
            ? null
            : formatRelativeDiscussionDateTime(discussion.createdAt),
        coverOverlay: discussion.isClosed
            ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: const Center(
                    child: Text(
                      '마감',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        content: discussion.isHidden
            ? const Text(
                '숨김 처리된 토론입니다.',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    discussion.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textStrong,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    discussion.isSpoiler
                        ? '스포일러가 포함된 토론입니다'
                        : (discussion.previewText ?? ''),
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
