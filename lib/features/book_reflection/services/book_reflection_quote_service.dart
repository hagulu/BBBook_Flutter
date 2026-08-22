import 'package:flutter_quill/flutter_quill.dart';

/// 연속된 인용 줄을 하나의 묶음으로 토글한다.
class BookReflectionQuoteService {
  const BookReflectionQuoteService();

  /// 연속된 인용 묶음마다 첫 줄의 문서 오프셋만 반환한다.
  List<int> firstQuoteLineOffsets(Document document) {
    final starts = <int>[];
    var offset = 0;
    var lineStart = 0;
    var previousLineWasQuote = false;
    for (final operation in document.toDelta().toList()) {
      final data = operation.data;
      if (data is! String) {
        offset++;
        continue;
      }
      final isQuoteOperation =
          operation.attributes?[Attribute.blockQuote.key] == true;
      for (final codeUnit in data.codeUnits) {
        if (codeUnit == 0x0A) {
          if (isQuoteOperation && !previousLineWasQuote) {
            starts.add(lineStart);
          }
          previousLineWasQuote = isQuoteOperation;
          lineStart = offset + 1;
        }
        offset++;
      }
    }
    return starts;
  }

  bool isSelectionInQuote(QuillController controller) {
    final selection = controller.selection;
    if (!selection.isCollapsed) {
      return controller.getSelectionStyle().attributes.containsKey(
        Attribute.blockQuote.key,
      );
    }

    final document = controller.document;
    final queryOffset = selection.extentOffset.clamp(0, document.length - 1);
    final line = document.queryChild(queryOffset).node;
    final quoteBlock = line?.parent;
    return quoteBlock is Block &&
        quoteBlock.style.attributes.containsKey(Attribute.blockQuote.key);
  }

  void toggle(QuillController controller) {
    final isActive = isSelectionInQuote(controller);
    controller.skipRequestKeyboard = true;

    if (!isActive) {
      controller.formatSelection(Attribute.blockQuote);
      return;
    }

    final document = controller.document;
    final queryOffset = controller.selection.extentOffset.clamp(
      0,
      document.length - 1,
    );
    final line = document.queryChild(queryOffset).node;
    final quoteBlock = line?.parent;
    if (quoteBlock is Block &&
        quoteBlock.style.attributes.containsKey(Attribute.blockQuote.key)) {
      controller.formatText(
        quoteBlock.documentOffset,
        quoteBlock.length,
        Attribute.clone(Attribute.blockQuote, null),
      );
      return;
    }

    controller.formatSelection(Attribute.clone(Attribute.blockQuote, null));
  }
}
