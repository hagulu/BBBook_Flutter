import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_confirm.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../book_record/screens/widgets/record_section_card.dart';
import '../../../book_record/screens/widgets/star_rating.dart';
import '../../models/book_review.dart';
import '../../providers/book_detail_providers.dart';
import 'report_dialog.dart';
import 'review_edit_dialog.dart';
import 'review_item.dart';

/// 미리보기로 노출할 최대 리뷰 개수. 전체 목록은 "더보기"로 진입하는 별도
/// 화면(TODO: 미구현)에서 커서 기반 페이지네이션으로 보여준다.
const _kPreviewCount = 3;

/// 커뮤니티 리뷰 섹션(book-detail.md `CommunityReviews` 대응). 토론/공개
/// 독후감 탭은 해당 기능이 아직 이관되지 않아 이번 범위에서 제외하고(사용자
/// 확인 사항), 이 섹션만 책 상세 화면에 직접 붙인다.
///
/// 작성 폼은 화면에 포함하지 않는다(사용자 확인 사항) — 조회 전용으로,
/// 최대 [_kPreviewCount]개만 보여주고 "더보기"는 전체 리스트 화면(미구현)
/// 진입 지점만 남겨둔다.
class CommunityReviewsSection extends ConsumerWidget {
  const CommunityReviewsSection({super.key, required this.isbn13});

  final String isbn13;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reviewsControllerProvider(isbn13));
    final controller = ref.read(reviewsControllerProvider(isbn13).notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DiscussionEntryButtons(
          // TODO: 실제 개수는 독후감/토론 API 연동 후 채운다. 지금은 버튼
          // 구조와 배지 위치를 보여주기 위한 샘플 값이다.
          onOpenReflections: () => _handleShowPlaceholder(context, '독후감'),
          onOpenDiscussions: () => _handleShowPlaceholder(context, '주제 토론'),
          reflectionCount: 12,
          discussionCount: 5,
        ),
        const SizedBox(height: 20),
        const Text(
          '커뮤니티 리뷰',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: AppColors.textStrong,
          ),
        ),
        const SizedBox(height: 12),
        switch (state) {
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RatingSummary(items: value.items),
              const SizedBox(height: 12),
              _ReviewsList(
                state: value,
                onToggleLike: (review) => _handleToggleLike(context, controller, review),
                onEdit: (review) => _handleEdit(context, controller, review),
                onDelete: (review) => _handleDelete(context, controller, review),
                onReport: (review) => _handleReport(context, controller, review),
                onShowMore: () => _handleShowMore(context),
              ),
            ],
          ),
          AsyncError() => Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  const Text(
                    '리뷰를 불러오지 못했습니다.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(reviewsControllerProvider(isbn13)),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            ),
          ),
          _ => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '불러오는 중',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ),
        },
      ],
    );
  }

  Future<void> _handleToggleLike(
    BuildContext context,
    ReviewsController controller,
    BookReview review,
  ) async {
    try {
      await controller.toggleLike(review);
    } on ApiException catch (e) {
      if (context.mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _handleEdit(
    BuildContext context,
    ReviewsController controller,
    BookReview review,
  ) async {
    final result = await showReviewEditDialog(context, review: review);
    if (result == null) return;
    try {
      await controller.updateReview(
        review,
        rating: result.rating,
        clearRating: result.clearRating,
        content: result.content,
        isSpoiler: result.isSpoiler,
      );
    } on ApiException catch (e) {
      if (context.mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _handleDelete(
    BuildContext context,
    ReviewsController controller,
    BookReview review,
  ) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '리뷰 삭제',
      message: '이 리뷰를 삭제할까요? 삭제하면 되돌릴 수 없습니다.',
      confirmText: '삭제',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await controller.deleteReview(review.id);
    } on ApiException catch (e) {
      if (context.mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _handleReport(
    BuildContext context,
    ReviewsController controller,
    BookReview review,
  ) async {
    final submission = await showReportDialog(context);
    if (submission == null) return;
    try {
      await controller.reportReview(
        review.id,
        reason: submission.reason.apiValue,
        content: submission.content,
      );
      if (context.mounted) AppSnackBar.success(context, '신고가 접수되었습니다.');
    } on ApiException catch (e) {
      if (context.mounted) AppSnackBar.error(context, e.message);
    }
  }

  void _handleShowMore(BuildContext context) => _handleShowPlaceholder(context, '전체 리뷰 목록');

  // TODO: 독후감/토론/전체 리뷰 목록 화면 구현 후 각각 해당 화면으로 이동.
  void _handleShowPlaceholder(BuildContext context, String label) {
    AppSnackBar.info(context, '$label 화면은 준비 중입니다.');
  }
}

/// 평균 별점 요약. 서버에 별도 집계 API가 없어 현재 로드된 리뷰(최대 20건,
/// [ReviewsController.build] 기준) 안의 평점만으로 계산한 근사값이다.
class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.items});

  final List<BookReview> items;

  @override
  Widget build(BuildContext context) {
    final rated = items.where((r) => r.rating != null).toList();
    if (rated.isEmpty) return const SizedBox.shrink();

    final average = rated.map((r) => r.rating!).reduce((a, b) => a + b) / rated.length;

    return Row(
      children: [
        StarRatingDisplay(
          rating: average,
          size: 15,
          filledColor: AppColors.accentGraphic,
        ),
        const SizedBox(width: 6),
        Text(
          average.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textStrong,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '(최근 ${rated.length}건)',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// 독후감/주제 토론 목록으로 이동하는 진입 버튼. 두 기능 모두 아직 이관되지
/// 않아(사용자 확인 사항) 지금은 버튼과 개수 배지 구조만 만들고 눌렀을 때는
/// 준비 중 안내만 띄운다.
class _DiscussionEntryButtons extends StatelessWidget {
  const _DiscussionEntryButtons({
    required this.onOpenReflections,
    required this.onOpenDiscussions,
    required this.reflectionCount,
    required this.discussionCount,
  });

  final VoidCallback onOpenReflections;
  final VoidCallback onOpenDiscussions;
  final int reflectionCount;
  final int discussionCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _EntryButton(
            icon: PhosphorIconsRegular.notebook,
            label: '독후감',
            count: reflectionCount,
            onTap: onOpenReflections,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _EntryButton(
            icon: PhosphorIconsRegular.chatsCircle,
            label: '주제 토론',
            count: discussionCount,
            onTap: onOpenDiscussions,
          ),
        ),
      ],
    );
  }
}

/// `ReadingStatusTile`(책 기록 상세)과 같은 구성 — 원형 아이콘 배지 + 라벨 +
/// 강조된 값 — 을 카드(`RecordSectionCard`)에 가로로 담아 진입 버튼으로 쓴다.
class _EntryButton extends StatelessWidget {
  const _EntryButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RecordSectionCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.accentSurface.withValues(alpha: 0.35),
                child: Icon(icon, color: AppColors.accentForeground, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      '$count개',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textStrong,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewsList extends StatelessWidget {
  const _ReviewsList({
    required this.state,
    required this.onToggleLike,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
    required this.onShowMore,
  });

  final ReviewsState state;
  final void Function(BookReview review) onToggleLike;
  final void Function(BookReview review) onEdit;
  final void Function(BookReview review) onDelete;
  final void Function(BookReview review) onReport;
  final VoidCallback onShowMore;

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '아직 리뷰가 없습니다',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    final previewItems = state.items.take(_kPreviewCount).toList();
    final hasMore = state.items.length > _kPreviewCount || state.hasNext;

    return Column(
      children: [
        for (final review in previewItems) ...[
          ReviewItem(
            key: ValueKey(review.id),
            review: review,
            onToggleLike: () => onToggleLike(review),
            onEdit: () => onEdit(review),
            onDelete: () => onDelete(review),
            onReport: () => onReport(review),
          ),
          const SizedBox(height: 10),
        ],
        if (hasMore)
          TextButton(
            onPressed: onShowMore,
            child: const Text('더보기'),
          ),
        if (state.isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '불러오는 중...',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
