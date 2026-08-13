import 'package:flutter/material.dart';

import '../../../book_record/models/record_labels.dart';
import '../../../book_record/screens/widgets/icon_option_selector.dart';
import '../../../book_record/screens/widgets/record_dialog_shell.dart';
import '../../../bookshelf/models/book_status.dart';

/// 서재 담기 상태 선택 팝업. book-detail.md 기준 읽고싶음/읽는 중/다 읽음
/// 3종만 노출한다(멈춤/중단은 책 기록 화면에서만 선택 가능 — book-record.md).
/// 책 검색의 "직접 등록" 다이얼로그에서도 동일하게 재사용한다.
Future<BookStatus?> showAddStatusDialog(BuildContext context) {
  return showModalBottomSheet<BookStatus>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => RecordDialogShell(
      title: '서재에 담기',
      content: IconOptionSelector<BookStatus>(
        options: [
          for (final status in const [
            BookStatus.wantToRead,
            BookStatus.reading,
            BookStatus.finished,
          ])
            IconOption(value: status, icon: status.icon, label: status.label),
        ],
        selected: null,
        onSelected: (status) => Navigator.of(context).pop(status),
      ),
    ),
  );
}
