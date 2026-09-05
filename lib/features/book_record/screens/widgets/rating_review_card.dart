import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/patch_field.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/models/book_item.dart';
import '../../../bookshelf/models/record_patch.dart';
import '../../providers/book_record_providers.dart';
import 'meta_dialogs.dart';
import 'record_section_card.dart';
import 'star_rating.dart';

/// 내 평점(탭 즉시 저장) + 한줄 평(바텀시트 입력, 저장 시 반영).
///
/// 완독 상태에서만 노출된다(호출부 `book_record_screen.dart` 참고) — 완독
/// 확인 팝업에서 입력한 값도 결국 이 필드에 반영되므로, 완독 이후에는 여기서
/// 계속 고쳐 쓸 수 있다.
class RatingReviewCard extends ConsumerWidget {
  const RatingReviewCard({
    super.key,
    required this.userBookId,
    required this.book,
  });

  final int userBookId;
  final BookItem book;

  /// 별점 입력은 같은 별을 다시 탭하면 0(평가 취소)이 된다 — 그건 "0점"이
  /// 아니라 "평가를 지웠다"는 뜻이라 명시적 null로 삭제한다.
  Future<void> _saveRating(WidgetRef ref, double rating) {
    return ref
        .read(bookRecordControllerProvider(userBookId).notifier)
        .updateRecord(
          RecordPatch(
            myRating: rating == 0
                ? const PatchField.clear()
                : PatchField.value(rating),
          ),
        );
  }

  Future<void> _editReview(BuildContext context, WidgetRef ref) async {
    final result = await showShortReviewDialog(
      context,
      initialValue: book.shortReview,
    );
    if (result == null || !context.mounted) return;
    final trimmed = result.trim();
    if (trimmed == (book.shortReview ?? '')) return;
    await ref
        .read(bookRecordControllerProvider(userBookId).notifier)
        .updateRecord(
          // 입력을 비웠으면 "지움"(명시적 null)이다 — 빈 문자열을 그대로
          // 보내면 서버가 삭제가 아니라 빈 값으로 저장한다.
          RecordPatch(
            shortReview: trimmed.isEmpty
                ? const PatchField.clear()
                : PatchField.value(trimmed),
          ),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasReview = book.shortReview != null && book.shortReview!.isNotEmpty;
    return RecordSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('내 평점'),
          const SizedBox(height: 2),
          StarRatingInput(
            rating: book.myRating ?? 0,
            onChanged: (rating) => _saveRating(ref, rating),
          ),
          const SizedBox(height: 10),
          const SectionLabel('한줄 평'),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _editReview(context, ref),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                hasReview ? book.shortReview! : '이 책에 대한 한 줄 평을 남겨보세요.',
                // 전체 내용은 탭하면 열리는 편집 바텀시트에서 볼 수 있으니,
                // 여기서는 미리보기 높이를 제한해 아래 메타 정보·태그를
                // 밀어내지 않게 한다.
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: hasReview
                      ? AppColors.textBody
                      : AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
