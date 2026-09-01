import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/community_content.dart';
import '../../../book_record/screens/widgets/star_rating.dart';
import '../../../discussion/screens/widgets/discussion_common.dart';
import '../../../discussion/utils/discussion_date.dart';
import '../../models/my_review_summary.dart';
import 'my_content_card_layout.dart';

/// "내가 작성한 독자평" 목록 카드(`my-content-screens.md` §3-1).
///
/// 다른 목록과 달리 상세로 이동하는 곳이 없어 카드 전체가 탭 불가능한
/// 정보 표시 전용 카드다.
class MyReviewCard extends StatelessWidget {
  const MyReviewCard({super.key, required this.review});

  final MyReviewSummary review;

  @override
  Widget build(BuildContext context) {
    return CommunityContentCard(
      child: MyContentCardLayout(
        book: review.book,
        dateLabel: formatRelativeDiscussionDateTime(review.createdAt),
        content: _ReviewBody(review: review),
      ),
    );
  }
}

class _ReviewBody extends StatefulWidget {
  const _ReviewBody({required this.review});

  final MyReviewSummary review;

  @override
  State<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends State<_ReviewBody> {
  bool _spoilerRevealed = false;

  @override
  Widget build(BuildContext context) {
    final review = widget.review;

    if (review.isHidden) {
      return const Text(
        '숨김 처리된 리뷰입니다.',
        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
      );
    }

    final content = review.content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (review.rating != null) ...[
          StarRatingDisplay(
            rating: review.rating!,
            size: 13,
            filledColor: AppColors.accentGraphic,
          ),
          if (content != null) const SizedBox(height: 6),
        ],
        if (content != null)
          if (review.isSpoiler && !_spoilerRevealed)
            InkWell(
              onTap: () => setState(() => _spoilerRevealed = true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIconsRegular.eyeSlash,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '스포일러가 포함되어 있어요. 눌러서 보기',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (review.isSpoiler) ...[
              const DiscussionBadge.spoiler(),
              const SizedBox(height: 6),
            ],
            Text(
              content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textBody,
                height: 1.4,
              ),
            ),
          ],
      ],
    );
  }
}
