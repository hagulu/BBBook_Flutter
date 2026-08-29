import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../shared/widgets/app_snackbar.dart';
import '../../discussion/screens/discussion_list_screen.dart';
import '../../public_reflection/screens/public_reflection_list_screen.dart';
import 'widgets/entry_button.dart';

/// 책 기록 상세의 "생각나눔" 탭. 이 책에 대해 다른 독자와 나누는 콘텐츠
/// (독자평/독후감/토론) 목록으로 넘어가는 진입 버튼만 모아 둔다.
///
/// 독자평은 아직 준비 중이며, 공개 독후감과 주제 토론은 ISBN 기준 목록으로
/// 연결한다.
class BookSharingList extends StatelessWidget {
  const BookSharingList({
    super.key,
    required this.bookTitle,
    required this.isbn13,
  });

  final String bookTitle;

  /// 공개 독후감과 토론은 ISBN 기준 API라 직접 등록한 책(ISBN 없음)에서는
  /// 진입할 수 없다.
  final String? isbn13;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('book-record-sharing'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        EntryButton(
          icon: PhosphorIconsRegular.star,
          label: '독자평',
          onTap: () => _showPlaceholder(context, '독자평'),
        ),
        const SizedBox(height: 12),
        EntryButton(
          icon: PhosphorIconsRegular.notebook,
          label: '독후감',
          onTap: () => _openReflections(context),
        ),
        const SizedBox(height: 12),
        EntryButton(
          icon: PhosphorIconsRegular.chatsCircle,
          label: '토론',
          onTap: () => _openDiscussions(context),
        ),
      ],
    );
  }

  void _openDiscussions(BuildContext context) {
    final isbn = isbn13;
    if (isbn == null || isbn.isEmpty) {
      AppSnackBar.info(context, 'ISBN이 없는 책은 토론을 이용할 수 없습니다.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DiscussionListScreen(isbn13: isbn, bookTitle: bookTitle),
      ),
    );
  }

  void _openReflections(BuildContext context) {
    final isbn = isbn13;
    if (isbn == null || isbn.isEmpty) {
      AppSnackBar.info(context, 'ISBN이 없는 책은 공개 독후감을 조회할 수 없습니다.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PublicReflectionListScreen(isbn13: isbn, bookTitle: bookTitle),
      ),
    );
  }

  // TODO: 독자평 목록 화면 구현 후 해당 화면으로 이동.
  void _showPlaceholder(BuildContext context, String label) {
    AppSnackBar.info(context, '$label 화면은 준비 중입니다.');
  }
}
