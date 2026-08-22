import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../book_note/models/book_note.dart';
import '../../book_note/utils/memo_highlight.dart';

/// 노트 메모의 타입과 강조 마크업을 Quill 문서 서식으로 변환해 삽입한다.
class BookReflectionMemoInsertService {
  const BookReflectionMemoInsertService();

  static const highlightColorValue = '#fef08a';

  bool insert(
    QuillController controller,
    BookNoteMemo memo, {
    TextSelection? selection,
  }) {
    final parsed = parseMemoHighlight(memo.content);
    if (parsed.plainText.trim().isEmpty) return false;

    final documentText = controller.document.toPlainText();
    final currentSelection = selection ?? controller.selection;
    final start = currentSelection.start.clamp(0, documentText.length - 1);
    final end = currentSelection.end.clamp(start, documentText.length - 1);
    final isQuote = memo.type == BookNoteMemoType.quote;
    final needsLeadingNewline =
        isQuote && start > 0 && documentText.codeUnitAt(start - 1) != 0x0A;
    final needsTrailingNewline =
        isQuote &&
        end < documentText.length &&
        documentText.codeUnitAt(end) != 0x0A;
    final leading = needsLeadingNewline ? '\n' : '';
    final trailing = needsTrailingNewline ? '\n' : '';
    final insertedText = '$leading${parsed.plainText}$trailing';
    final contentStart = start + leading.length;

    controller
      ..skipRequestKeyboard = true
      ..replaceText(
        start,
        end - start,
        insertedText,
        TextSelection.collapsed(offset: start + insertedText.length),
      )
      ..formatText(
        contentStart,
        parsed.plainText.length,
        const BackgroundAttribute(null),
      );

    for (final range in parsed.ranges) {
      controller.formatText(
        contentStart + range.start,
        range.end - range.start,
        const BackgroundAttribute(highlightColorValue),
      );
    }
    if (isQuote) {
      controller.formatText(
        contentStart,
        parsed.plainText.length,
        Attribute.blockQuote,
      );
    }
    return true;
  }
}
