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
///
/// [onSubmit]이 성공(true)을 반환하면 시트를 닫고, 실패(false)면 입력을 그대로
/// 둔 채 다시 저장할 수 있게 열어 둔다(에러 안내는 호출부가 스낵바로 표시) —
/// 시트를 먼저 닫고 요청하면 실패했을 때 방금 쓴 내용이 사라진다.
Future<void> showReviewEditDialog(
  BuildContext context, {
  required BookReview review,
  required Future<bool> Function(ReviewEditResult result) onSubmit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ReviewEditDialog(review: review, onSubmit: onSubmit),
  );
}

/// 새 독자평 작성 모달. [onSubmit]은 [showReviewEditDialog]와 같다.
Future<void> showReviewCreateDialog(
  BuildContext context, {
  required Future<bool> Function(ReviewEditResult result) onSubmit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ReviewEditDialog(review: null, onSubmit: onSubmit),
  );
}

class _ReviewEditDialog extends StatefulWidget {
  const _ReviewEditDialog({required this.review, required this.onSubmit});

  final BookReview? review;
  final Future<bool> Function(ReviewEditResult result) onSubmit;

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
  bool _isSubmitting = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSubmitting) return;
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      setState(() => _errorText = '리뷰 내용을 입력해주세요.');
      return;
    }
    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });
    final success = await widget.onSubmit(
      ReviewEditResult(
        rating: _rating == 0 ? null : _rating,
        clearRating: _rating == 0,
        content: content,
        isSpoiler: _isSpoiler,
      ),
    );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 요청 중에는 뒤로 가기·바깥 탭으로 닫지 않는다(이미 나간 요청은 취소되지
    // 않아, 닫힌 줄 알고 다시 쓰면 독자평이 중복된다). 아래로 끌어 닫기는
    // PopScope를 거치지 않고 시트가 직접 닫으므로, 요청 중에는 세로 드래그를
    // 이 시트가 먼저 가져가 막는다.
    return PopScope(
      canPop: !_isSubmitting,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _isSubmitting ? (_) {} : null,
        child: _buildShell(context),
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
    return RecordDialogShell(
      title: widget.review == null ? '독자평 작성' : '리뷰 수정',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 별점(5개 × 44px 터치 영역)과 스포일러 토글을 한 Row에 두면
          // 좁은 화면·큰 글자 배율에서 가로 폭이 모자라 RenderFlex가
          // 넘친다. Wrap을 써서 자리가 부족하면 스포일러 토글이 다음
          // 줄로 자연스럽게 내려가게 한다.
          //
          // 요청 중에는 입력을 잠근다 — 보낸 값은 저장 시작 시점의 것이라,
          // 그 사이 바꾼 값은 성공해 시트가 닫히면 저장되지 않고 사라진다.
          IgnorePointer(
            ignoring: _isSubmitting,
            child: Wrap(
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
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            readOnly: _isSubmitting,
            maxLength: 150,
            maxLines: 4,
            decoration: InputDecoration(
              isDense: true,
              hintText: '리뷰 내용을 입력해주세요',
              counterStyle: TextStyle(
                color: AppColors.of(context).textMuted,
                fontSize: 12,
              ),
            ),
          ),
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _errorText!,
                style: TextStyle(
                  color: AppColors.of(context).error,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      buttons: [
        RecordDialogButton(
          label: widget.review == null
              ? (_isSubmitting ? '등록 중' : '등록')
              : (_isSubmitting ? '저장 중' : '저장'),
          onPressed: _isSubmitting ? null : _save,
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
              ? AppColors.of(context).highlightGoldSurface
              : AppColors.of(context).surfaceSubtle,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.eyeSlash,
              size: 14,
              color: isSpoiler
                  ? AppColors.of(context).memoThoughtForeground
                  : AppColors.of(context).textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              '스포일러',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSpoiler
                    ? AppColors.of(context).memoThoughtForeground
                    : AppColors.of(context).textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
