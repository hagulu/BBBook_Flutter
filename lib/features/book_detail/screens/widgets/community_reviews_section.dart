import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_confirm.dart';
import '../../../book_record/screens/widgets/star_rating.dart';
import '../../models/book_review.dart';
import '../../providers/book_detail_providers.dart';
import 'report_dialog.dart';
import 'review_edit_dialog.dart';
import 'review_item.dart';

/// 커뮤니티 리뷰 섹션(book-detail.md `CommunityReviews` 대응). 토론/공개
/// 독후감 탭은 해당 기능이 아직 이관되지 않아 이번 범위에서 제외하고(사용자
/// 확인 사항), 이 섹션만 책 상세 화면에 직접 붙인다.
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
        const Text(
          '커뮤니티 리뷰',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: AppColors.titleText,
          ),
        ),
        const SizedBox(height: 12),
        _ReviewComposeForm(onSubmit: controller.submitReview),
        const SizedBox(height: 16),
        switch (state) {
          AsyncData(:final value) => _ReviewsList(
            state: value,
            onToggleLike: (review) => _handleToggleLike(context, controller, review),
            onEdit: (review) => _handleEdit(context, controller, review),
            onDelete: (review) => _handleDelete(context, controller, review),
            onReport: (review) => _handleReport(context, controller, review),
          ),
          AsyncError() => Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  const Text(
                    '리뷰를 불러오지 못했습니다.',
                    style: TextStyle(color: AppColors.tertiaryText),
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
                style: TextStyle(color: AppColors.tertiaryText),
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
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
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다.')));
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _ReviewsList extends StatelessWidget {
  const _ReviewsList({
    required this.state,
    required this.onToggleLike,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
  });

  final ReviewsState state;
  final void Function(BookReview review) onToggleLike;
  final void Function(BookReview review) onEdit;
  final void Function(BookReview review) onDelete;
  final void Function(BookReview review) onReport;

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '아직 리뷰가 없습니다',
            style: TextStyle(color: AppColors.tertiaryText),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final review in state.items) ...[
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
        if (state.isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '불러오는 중...',
              style: TextStyle(color: AppColors.tertiaryText, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _ReviewComposeForm extends StatefulWidget {
  const _ReviewComposeForm({required this.onSubmit});

  final Future<bool> Function({
    double? rating,
    required String content,
    required bool isSpoiler,
  })
  onSubmit;

  @override
  State<_ReviewComposeForm> createState() => _ReviewComposeFormState();
}

class _ReviewComposeFormState extends State<_ReviewComposeForm> {
  final _contentController = TextEditingController();
  double _rating = 0;
  bool _isSpoiler = false;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      setState(() => _errorText = '리뷰 내용을 입력해주세요.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      final reloaded = await widget.onSubmit(
        rating: _rating == 0 ? null : _rating,
        content: content,
        isSpoiler: _isSpoiler,
      );
      if (mounted) {
        _contentController.clear();
        setState(() {
          _rating = 0;
          _isSpoiler = false;
        });
        if (!reloaded) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('리뷰가 등록됐지만 목록을 새로고치지 못했습니다. 잠시 후 다시 확인해주세요.'),
            ),
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarRatingInput(
            rating: _rating,
            onChanged: (v) => setState(() => _rating = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contentController,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(
              isDense: true,
              hintText: '이 책에 대한 리뷰를 남겨보세요',
              counterText: '',
            ),
          ),
          Row(
            children: [
              Checkbox(
                value: _isSpoiler,
                onChanged: (v) => setState(() => _isSpoiler = v ?? false),
                visualDensity: VisualDensity.compact,
              ),
              const Text('스포일러 포함', style: TextStyle(fontSize: 13)),
              const Spacer(),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
                child: Text(_submitting ? '등록 중...' : '등록'),
              ),
            ],
          ),
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _errorText!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
