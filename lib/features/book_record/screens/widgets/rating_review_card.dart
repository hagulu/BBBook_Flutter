import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/patch_field.dart';
import '../../../bookshelf/models/book_item.dart';
import '../../../bookshelf/models/record_patch.dart';
import '../../providers/book_record_providers.dart';
import 'record_section_card.dart';
import 'star_rating.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 내 평점(탭 즉시 저장) + 개인 리뷰(포커스 아웃 시 저장).
///
/// `book-record.md` 스크린샷 기준 독서 상태(읽는 중이든 완독이든)와 무관하게
/// 항상 노출·편집 가능하다 — 완독 확인 팝업에서 입력한 값도 결국 이 필드에
/// 반영되므로, 완독 이후에도 여기서 계속 고쳐 쓸 수 있어야 자연스럽다.
class RatingReviewCard extends ConsumerStatefulWidget {
  const RatingReviewCard({
    super.key,
    required this.userBookId,
    required this.book,
  });

  final int userBookId;
  final BookItem book;

  @override
  ConsumerState<RatingReviewCard> createState() => _RatingReviewCardState();
}

class _RatingReviewCardState extends ConsumerState<RatingReviewCard> {
  late final _reviewController = TextEditingController(
    text: widget.book.shortReview ?? '',
  );
  final _reviewFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _reviewFocus.addListener(() {
      if (!_reviewFocus.hasFocus) _saveReview();
    });
  }

  @override
  void didUpdateWidget(covariant RatingReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.book.shortReview != oldWidget.book.shortReview &&
        !_reviewFocus.hasFocus) {
      _reviewController.text = widget.book.shortReview ?? '';
    }
  }

  @override
  void dispose() {
    _reviewController.dispose();
    _reviewFocus.dispose();
    super.dispose();
  }

  /// 별점 입력은 같은 별을 다시 탭하면 0(평가 취소)이 된다 — 그건 "0점"이
  /// 아니라 "평가를 지웠다"는 뜻이라 명시적 null로 삭제한다.
  Future<void> _saveRating(double rating) {
    return ref
        .read(bookRecordControllerProvider(widget.userBookId).notifier)
        .updateRecord(
          RecordPatch(
            myRating: rating == 0
                ? const PatchField.clear()
                : PatchField.value(rating),
          ),
        );
  }

  Future<void> _saveReview() {
    final trimmed = _reviewController.text.trim();
    if (trimmed == (widget.book.shortReview ?? '')) return Future.value();
    return ref
        .read(bookRecordControllerProvider(widget.userBookId).notifier)
        .updateRecord(
          RecordPatch(
            // 입력을 비웠으면 "지움"(명시적 null)이다 — 빈 문자열을 그대로
            // 보내면 서버가 삭제가 아니라 빈 값으로 저장한다.
            shortReview: trimmed.isEmpty
                ? const PatchField.clear()
                : PatchField.value(trimmed),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return RecordSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('내 평점', icon: PhosphorIconsRegular.star),
          const SizedBox(height: 2),
          StarRatingInput(
            rating: widget.book.myRating ?? 0,
            onChanged: _saveRating,
          ),
          const SizedBox(height: 10),
          const SectionLabel('개인 리뷰', icon: PhosphorIconsRegular.notePencil),
          const SizedBox(height: 8),
          TextField(
            controller: _reviewController,
            focusNode: _reviewFocus,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(
              isDense: true,
              hintText: '이 책에 대한 짧은 리뷰를 남겨보세요.',
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}
