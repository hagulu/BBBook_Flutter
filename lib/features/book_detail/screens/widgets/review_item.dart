import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/community_content.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../../book_record/screens/widgets/star_rating.dart';
import '../../../discussion/utils/discussion_date.dart';
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

  /// 공감 요청이 진행 중이면 null을 넘겨 중복 탭(POST/DELETE 경합)을 막는다.
  final VoidCallback? onToggleLike;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  State<ReviewItem> createState() => _ReviewItemState();
}

class _ReviewItemState extends State<ReviewItem> {
  bool _spoilerRevealed = false;

  Future<void> _openMenuSheet(BuildContext context) async {
    final action = await showModalBottomSheet<_ReviewMenuAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => RecordDialogShell(
        title: '리뷰 관리',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CommunityMenuTile(
              icon: PhosphorIconsRegular.pencilSimple,
              label: '수정',
              onTap: () => Navigator.pop(sheetContext, _ReviewMenuAction.edit),
            ),
            CommunityMenuTile(
              icon: PhosphorIconsRegular.trash,
              label: '삭제',
              color: AppColors.error,
              onTap: () =>
                  Navigator.pop(sheetContext, _ReviewMenuAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ReviewMenuAction.edit:
        widget.onEdit();
      case _ReviewMenuAction.delete:
        widget.onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommunityAuthorRow(
            nickname: review.user.nickname,
            profileImageUrl: review.user.profileImageUrl,
            dateLabel: formatRelativeDiscussionDate(review.createdAt),
            trailing: review.isHidden
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (review.rating != null) ...[
                        StarRatingDisplay(
                          rating: review.rating!,
                          size: 14,
                          filledColor: AppColors.accentGraphic,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (review.isMine)
                        CommunityMoreButton(
                          tooltip: '리뷰 메뉴',
                          iconSize: 18,
                          onTap: () => _openMenuSheet(context),
                        )
                      else
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          icon: const Icon(
                            PhosphorIconsRegular.flag,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          onPressed: widget.onReport,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          if (review.isHidden)
            const Text(
              '숨김 처리된 리뷰입니다.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            )
          else ...[
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
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textBody,
                  height: 1.4,
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: CommunityLikeInline(
                isLiked: review.isLiked,
                likeCount: review.likeCount,
                onTap: widget.onToggleLike,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _ReviewMenuAction { edit, delete }
