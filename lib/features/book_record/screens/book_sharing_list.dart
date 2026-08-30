import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../shared/widgets/app_snackbar.dart';
import '../../book_community/screens/widgets/book_community_preview_section.dart';
import 'widgets/entry_button.dart';

/// 책 기록 상세의 "생각나눔" 탭.
///
/// ISBN이 있으면 [BookCommunityPreviewSection]을 보여준다. 이미 내 책장에
/// 있는 책이라 `showReviewButton: true`로 독자평 버튼을 개수 무관하게 항상
/// 띄우고, `userBookId`로 내가 이미 쓴 공개 독후감 수를 독후감 배지에서
/// 뺀다(그 책의 독후감 탭에 따로 보이므로 여기서는 "다른 사람이 쓴 개수"만
/// 의미가 있다). 독자평/공개 독후감/토론 모두 ISBN 기준 API라 직접 등록한
/// 책(ISBN 없음)에서는 진입할 수 없어, 안내만 하는 진입 버튼으로 대신한다.
class BookSharingList extends StatelessWidget {
  const BookSharingList({
    super.key,
    required this.userBookId,
    required this.bookTitle,
    required this.isbn13,
  });

  final int userBookId;
  final String bookTitle;

  final String? isbn13;

  @override
  Widget build(BuildContext context) {
    final isbn = isbn13;
    return ListView(
      key: const PageStorageKey('book-record-sharing'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        if (isbn == null || isbn.isEmpty)
          const _NoIsbnEntryButtons()
        else
          BookCommunityPreviewSection(
            isbn13: isbn,
            bookTitle: bookTitle,
            userBookId: userBookId,
            showReviewButton: true,
          ),
      ],
    );
  }
}

class _NoIsbnEntryButtons extends StatelessWidget {
  const _NoIsbnEntryButtons();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EntryButton(
          icon: PhosphorIconsRegular.star,
          label: '독자평',
          onTap: () =>
              AppSnackBar.info(context, 'ISBN이 없는 책은 독자평을 이용할 수 없습니다.'),
        ),
        const SizedBox(height: 12),
        EntryButton(
          icon: PhosphorIconsRegular.notebook,
          label: '독후감',
          onTap: () =>
              AppSnackBar.info(context, 'ISBN이 없는 책은 공개 독후감을 조회할 수 없습니다.'),
        ),
        const SizedBox(height: 12),
        EntryButton(
          icon: PhosphorIconsRegular.chatsCircle,
          label: '토론',
          onTap: () => AppSnackBar.info(context, 'ISBN이 없는 책은 토론을 이용할 수 없습니다.'),
        ),
      ],
    );
  }
}
