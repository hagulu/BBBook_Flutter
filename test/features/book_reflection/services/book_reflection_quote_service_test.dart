import 'package:bbbook/features/book_reflection/services/book_reflection_quote_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = BookReflectionQuoteService();

  test('연속 인용 가운데에서 해제하면 인용 묶음 전체를 해제한다', () {
    final controller = QuillController(
      document: Document.fromJson([
        {'insert': '일반\n'},
        {'insert': '인용 A'},
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
        {'insert': '인용 B'},
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
        {'insert': '인용 C'},
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
        {'insert': '다음 본문\n'},
      ]),
      selection: const TextSelection.collapsed(offset: 11),
    );
    addTearDown(controller.dispose);

    service.toggle(controller);

    final ops = controller.document.toDelta().toJson();
    expect(
      ops.any(
        (op) => (op['attributes'] as Map?)?.containsKey('blockquote') == true,
      ),
      isFalse,
    );
    expect(controller.document.toPlainText(), '일반\n인용 A\n인용 B\n인용 C\n다음 본문\n');
  });

  test('일반 줄에서는 현재 줄에 인용을 적용한다', () {
    final controller = QuillController(
      document: Document.fromJson([
        {'insert': '첫 줄\n둘째 줄\n'},
      ]),
      selection: const TextSelection.collapsed(offset: 1),
    );
    addTearDown(controller.dispose);

    service.toggle(controller);

    expect(controller.document.toDelta().toJson(), [
      {'insert': '첫 줄'},
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
      {'insert': '둘째 줄\n'},
    ]);
  });

  test('연속 인용 묶음마다 첫 줄 오프셋만 반환한다', () {
    final document = Document.fromJson([
      {'insert': '일반\n'},
      {'insert': '인용 A'},
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
      {'insert': '인용 B'},
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
      {'insert': '사이\n'},
      {'insert': '인용 C'},
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
    ]);

    expect(service.firstQuoteLineOffsets(document), [3, 16]);
  });
}
