import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../book_record/screens/widgets/star_rating.dart';
import '../../models/book_review.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 커뮤니티 리뷰 카드 한 건(book-detail.md `CommunityReviews` 대응).
///
/// 작성자 아바타/닉네임 클릭 시 다른 사용자 완독 책장으로 이동하는 `UserMenu`
/// 팝오버는 해당 기능(public-finished-shelf)이 아직 이관되지 않아 이번
/// 범위에서 제외한다(사용자 확인 사항).
class ReviewItem extends StatefulWidget {
  const ReviewItem({
    super.key,
    required this.review,
    required this.onToggleLike,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
  });

  final BookReview review;
  final VoidCallback onToggleLike;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  State<ReviewItem> createState() => _ReviewItemState();
}

class _ReviewItemState extends State<ReviewItem> {
  bool _spoilerRevealed = false;

  @override
  Widget build(BuildContext context) {
    final review = widget.review;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.accentSurface,
                backgroundImage: review.user.profileImageUrl != null
                    ? NetworkImage(review.user.profileImageUrl!)
                    : null,
                child: review.user.profileImageUrl == null
                    ? const Icon(
                        PhosphorIconsRegular.user,
                        size: 16,
                        color: AppColors.accentForeground,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.user.nickname ?? '알 수 없음',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textStrong,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (review.isHidden)
                const SizedBox.shrink()
              else if (review.isMine)
                PopupMenuButton<_ReviewMenuAction>(
                  icon: const Icon(
                    PhosphorIconsRegular.dotsThreeVertical,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _ReviewMenuAction.edit:
                        widget.onEdit();
                      case _ReviewMenuAction.delete:
                        widget.onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _ReviewMenuAction.edit,
                      child: Text('수정'),
                    ),
                    PopupMenuItem(
                      value: _ReviewMenuAction.delete,
                      child: Text('삭제'),
                    ),
                  ],
                )
              else
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(
                    PhosphorIconsRegular.flag,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  onPressed: widget.onReport,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (review.isHidden)
            const Text(
              '숨김 처리된 리뷰입니다.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            )
          else ...[
            if (review.rating != null) ...[
              StarRatingDisplay(
                rating: review.rating!,
                size: 14,
                filledColor: AppColors.accentGraphic,
              ),
              const SizedBox(height: 6),
            ],
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
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Text(
                review.content ?? '',
                style: const TextStyle(fontSize: 14, color: AppColors.textBody, height: 1.4),
              ),
            const SizedBox(height: 8),
            InkWell(
              onTap: widget.onToggleLike,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      review.isLiked
                          ? PhosphorIconsFill.heart
                          : PhosphorIconsRegular.heart,
                      size: 16,
                      color: review.isLiked
                          ? AppColors.error
                          : AppColors.controlInactive,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${review.likeCount}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _ReviewMenuAction { edit, delete }
