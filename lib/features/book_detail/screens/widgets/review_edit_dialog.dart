import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../../book_record/screens/widgets/star_rating.dart';
import '../../models/book_review.dart';

class ReviewEditResult {
  const ReviewEditResult({
    this.rating,
    this.clearRating = false,
    required this.content,
    required this.isSpoiler,
  });

  final double? rating;
  final bool clearRating;
  final String content;
  final bool isSpoiler;
}

/// 본인 리뷰 수정 모달(book-detail.md `CommunityReviews` "···" 메뉴 → 수정).
Future<ReviewEditResult?> showReviewEditDialog(
  BuildContext context, {
  required BookReview review,
}) {
  return showModalBottomSheet<ReviewEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ReviewEditDialog(review: review),
  );
}

/// 새 독자평 작성 모달.
Future<ReviewEditResult?> showReviewCreateDialog(BuildContext context) {
  return showModalBottomSheet<ReviewEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _ReviewEditDialog(review: null),
  );
}

class _ReviewEditDialog extends StatefulWidget {
  const _ReviewEditDialog({required this.review});

  final BookReview? review;

  @override
  State<_ReviewEditDialog> createState() => _ReviewEditDialogState();
}

class _ReviewEditDialogState extends State<_ReviewEditDialog> {
  late double _rating = widget.review?.rating ?? 0;
  late final _contentController = TextEditingController(
    text: widget.review?.content ?? '',
  );
  late bool _isSpoiler = widget.review?.isSpoiler ?? false;
  String? _errorText;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      setState(() => _errorText = '리뷰 내용을 입력해주세요.');
      return;
    }
    Navigator.of(context).pop(
      ReviewEditResult(
        rating: _rating == 0 ? null : _rating,
        clearRating: _rating == 0,
        content: content,
        isSpoiler: _isSpoiler,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: widget.review == null ? '독자평 작성' : '리뷰 수정',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 별점(5개 × 44px 터치 영역)과 스포일러 토글을 한 Row에 두면
          // 좁은 화면·큰 글자 배율에서 가로 폭이 모자라 RenderFlex가
          // 넘친다. Wrap을 써서 자리가 부족하면 스포일러 토글이 다음
          // 줄로 자연스럽게 내려가게 한다.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              StarRatingInput(
                rating: _rating,
                onChanged: (v) => setState(() => _rating = v),
              ),
              _SpoilerToggle(
                isSpoiler: _isSpoiler,
                onTap: () => setState(() => _isSpoiler = !_isSpoiler),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            maxLength: 2000,
            maxLines: 4,
            decoration: const InputDecoration(
              isDense: true,
              hintText: '리뷰 내용을 입력해주세요',
              counterText: '',
            ),
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
      buttons: [
        RecordDialogButton(
          label: widget.review == null ? '등록' : '저장',
          onPressed: _save,
        ),
      ],
    );
  }
}

class _SpoilerToggle extends StatelessWidget {
  const _SpoilerToggle({required this.isSpoiler, required this.onTap});

  final bool isSpoiler;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSpoiler
              ? AppColors.highlightGoldSurface
              : AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.eyeSlash,
              size: 14,
              color: isSpoiler
                  ? AppColors.memoThoughtForeground
                  : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              '스포일러',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSpoiler
                    ? AppColors.memoThoughtForeground
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
