import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/community_content.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../../book_record/screens/widgets/star_rating.dart';
import '../../../discussion/utils/discussion_date.dart';
import '../../../public_bookshelf/widgets/author_profile_sheet.dart';
import '../../models/book_review.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 커뮤니티 리뷰 카드 한 건(book-detail.md `CommunityReviews` 대응).
///
/// 작성자 아바타/닉네임을 탭하면 웹의 `UserMenu`와 동일하게 완독 책장이
/// 공개된 사용자에 한해 시트를 띄워 완독 책장으로 이동한다.
class ReviewItem extends StatefulWidget {
  const ReviewItem({
    super.key,
    required this.review,
    required this.onToggleLike,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
    this.allowAccountActions = true,
    this.canEdit = true,
  });

  final BookReview review;

  /// 서버 계정이 필요한 액션(공감·신고·본인 글 관리)을 노출할지. 계정 없이
  /// 쓰는 사용자에게는 버튼 자체를 만들지 않는다.
  final bool allowAccountActions;
  final bool canEdit;

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
            if (widget.canEdit)
              CommunityMenuTile(
                icon: PhosphorIconsRegular.pencilSimple,
                label: '수정',
                onTap: () =>
                    Navigator.pop(sheetContext, _ReviewMenuAction.edit),
              ),
            CommunityMenuTile(
              icon: PhosphorIconsRegular.trash,
              label: '삭제',
              destructive: true,
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
            onTap: authorProfileSheetHandler(
              context,
              userId: review.user.id,
              nickname: review.user.nickname,
              isFinishedBooksPublic: review.user.isFinishedBooksPublic,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (review.rating != null) ...[
                  StarRatingDisplay(
                    rating: review.rating!,
                    size: 14,
                    filledColor: AppColors.of(context).accentGraphic,
                  ),
                  const SizedBox(width: 8),
                ],
                if (widget.allowAccountActions)
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
                      icon: Icon(
                        PhosphorIconsRegular.flag,
                        size: 16,
                        color: AppColors.of(context).textMuted,
                      ),
                      onPressed: widget.onReport,
                    ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (review.isSpoiler && !_spoilerRevealed)
            InkWell(
              onTap: () => setState(() => _spoilerRevealed = true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.of(context).surfaceSubtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIconsRegular.eyeSlash,
                      size: 14,
                      color: AppColors.of(context).textMuted,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '스포일러가 포함되어 있어요. 눌러서 보기',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.of(context).textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              review.content ?? '',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.of(context).textBody,
                height: 1.4,
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: widget.allowAccountActions
                ? CommunityLikeInline(
                    isLiked: review.isLiked,
                    likeCount: review.likeCount,
                    onTap: widget.onToggleLike,
                  )
                : CommunityLikeCount(likeCount: review.likeCount),
          ),
        ],
      ),
    );
  }
}

enum _ReviewMenuAction { edit, delete }
