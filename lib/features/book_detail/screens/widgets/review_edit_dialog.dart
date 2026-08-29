import 'package:flutter/material.dart';

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

class _ReviewEditDialog extends StatefulWidget {
  const _ReviewEditDialog({required this.review});

  final BookReview review;

  @override
  State<_ReviewEditDialog> createState() => _ReviewEditDialogState();
}

class _ReviewEditDialogState extends State<_ReviewEditDialog> {
  late double _rating = widget.review.rating ?? 0;
  late final _contentController = TextEditingController(
    text: widget.review.content ?? '',
  );
  late bool _isSpoiler = widget.review.isSpoiler;
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
      title: '리뷰 수정',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: StarRatingInput(
              rating: _rating,
              onChanged: (v) => setState(() => _rating = v),
            ),
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
          CheckboxListTile(
            value: _isSpoiler,
            onChanged: (v) => setState(() => _isSpoiler = v ?? false),
            activeColor: AppColors.accentForeground,
            checkColor: AppColors.surface,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              '스포일러 포함',
              style: TextStyle(fontSize: 13, color: AppColors.textBody),
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
      buttons: [RecordDialogButton(label: '저장', onPressed: _save)],
    );
  }
}
