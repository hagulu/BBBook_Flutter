import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/community_content.dart';
import '../models/book_review.dart';
import '../providers/book_detail_providers.dart';
import 'widgets/report_dialog.dart';
import 'widgets/review_edit_dialog.dart';
import 'widgets/review_item.dart';

/// ISBN13 한 권의 독자평 전체 목록(`/api/books/{isbn13}/reviews` 커서 기반).
///
/// 책 검색 상세의 커뮤니티 미리보기, 책 기록 상세의 생각나눔 탭 양쪽에서
/// "독자평" 진입 버튼으로 들어오는 공통 화면이다.
class BookReviewListScreen extends ConsumerStatefulWidget {
  const BookReviewListScreen({
    super.key,
    required this.isbn13,
    required this.bookTitle,
  });

  final String isbn13;
  final String bookTitle;

  @override
  ConsumerState<BookReviewListScreen> createState() =>
      _BookReviewListScreenState();
}

class _BookReviewListScreenState extends ConsumerState<BookReviewListScreen> {
  final _scrollController = ScrollController();
  final _pendingLikeIds = <int>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      ref.read(reviewsControllerProvider(widget.isbn13).notifier).loadMore();
    }
  }

  Future<void> _handleToggleLike(BookReview review) async {
    if (_pendingLikeIds.contains(review.id)) return;
    setState(() => _pendingLikeIds.add(review.id));
    try {
      await ref
          .read(reviewsControllerProvider(widget.isbn13).notifier)
          .toggleLike(review);
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } finally {
      if (mounted) setState(() => _pendingLikeIds.remove(review.id));
    }
  }

  Future<void> _handleCreate() async {
    final result = await showReviewCreateDialog(context);
    if (result == null || !mounted) return;
    try {
      final success = await ref
          .read(reviewsControllerProvider(widget.isbn13).notifier)
          .submitReview(
            rating: result.rating,
            content: result.content,
            isSpoiler: result.isSpoiler,
          );
      if (!mounted) return;
      if (success) {
        AppSnackBar.success(context, '독자평이 등록되었습니다.');
      } else {
        // submitReview()는 등록(POST) 자체가 성공한 뒤 첫 페이지 재조회만
        // 실패했을 때 false를 반환한다 — 여기서 "등록 실패"로 안내하면
        // 사용자가 같은 내용을 다시 등록해 중복 리뷰가 생길 수 있다.
        AppSnackBar.info(context, '독자평을 등록했어요. 목록은 잠시 후 새로고침해주세요.');
      }
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _handleEdit(BookReview review) async {
    final result = await showReviewEditDialog(context, review: review);
    if (result == null || !mounted) return;
    try {
      await ref
          .read(reviewsControllerProvider(widget.isbn13).notifier)
          .updateReview(
            review,
            rating: result.rating,
            clearRating: result.clearRating,
            content: result.content,
            isSpoiler: result.isSpoiler,
          );
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _handleDelete(BookReview review) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '리뷰 삭제',
      message: '이 리뷰를 삭제할까요? 삭제하면 되돌릴 수 없습니다.',
      confirmText: '삭제',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(reviewsControllerProvider(widget.isbn13).notifier)
          .deleteReview(review.id);
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _handleReport(BookReview review) async {
    final submission = await showReportDialog(context);
    if (submission == null || !mounted) return;
    try {
      await ref
          .read(reviewsControllerProvider(widget.isbn13).notifier)
          .reportReview(
            review.id,
            reason: submission.reason.apiValue,
            content: submission.content,
          );
      if (mounted) AppSnackBar.success(context, '신고가 접수되었습니다.');
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewsControllerProvider(widget.isbn13));

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(widget.bookTitle, subtitle: '독자평'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          AsyncData(:final value) => _ReviewList(
            scrollController: _scrollController,
            state: value,
            pendingLikeIds: _pendingLikeIds,
            onRefresh: () => ref
                .read(reviewsControllerProvider(widget.isbn13).notifier)
                .refresh(),
            onToggleLike: _handleToggleLike,
            onEdit: _handleEdit,
            onDelete: _handleDelete,
            onReport: _handleReport,
          ),
          AsyncError() => CommunityContentErrorState(
            message: '독자평을 불러오지 못했습니다.',
            onRetry: () =>
                ref.invalidate(reviewsControllerProvider(widget.isbn13)),
          ),
          _ => const CommunityContentLoadingState(),
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _handleCreate,
        tooltip: '독자평 쓰기',
        shape: const CircleBorder(),
        backgroundColor: AppColors.accentFill,
        foregroundColor: AppColors.textStrong,
        child: const Icon(PhosphorIconsRegular.plus),
      ),
    );
  }
}

class _ReviewList extends StatelessWidget {
  const _ReviewList({
    required this.scrollController,
    required this.state,
    required this.pendingLikeIds,
    required this.onRefresh,
    required this.onToggleLike,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
  });

  final ScrollController scrollController;
  final ReviewsState state;
  final Set<int> pendingLikeIds;
  final Future<void> Function() onRefresh;
  final void Function(BookReview review) onToggleLike;
  final void Function(BookReview review) onEdit;
  final void Function(BookReview review) onDelete;
  final void Function(BookReview review) onReport;

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty) {
      return CommunityContentEmptyList(
        message: '아직 등록된 독자평이 없습니다.',
        scrollController: scrollController,
        onRefresh: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const CommunityContentPageLoader();
          }
          final review = state.items[index];
          return ReviewItem(
            key: ValueKey(review.id),
            review: review,
            onToggleLike: pendingLikeIds.contains(review.id)
                ? null
                : () => onToggleLike(review),
            onEdit: () => onEdit(review),
            onDelete: () => onDelete(review),
            onReport: () => onReport(review),
          );
        },
      ),
    );
  }
}
