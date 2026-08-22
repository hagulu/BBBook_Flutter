import 'package:bbbook/features/book_note/models/book_note.dart';
import 'package:bbbook/features/book_reflection/services/book_reflection_memo_insert_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = BookReflectionMemoInsertService();

  test('메모 강조 마크업을 제거하고 해당 범위에 노란 배경을 적용한다', () {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);

    final inserted = service.insert(
      controller,
      _memo(type: BookNoteMemoType.summary, content: '앞 ::hl[[강조]] 뒤'),
      selection: const TextSelection.collapsed(offset: 0),
    );

    expect(inserted, isTrue);
    expect(controller.document.toPlainText(), '앞 강조 뒤\n');
    expect(controller.document.toDelta().toJson(), [
      {'insert': '앞 '},
      {
        'insert': '강조',
        'attributes': {
          'background': BookReflectionMemoInsertService.highlightColorValue,
        },
      },
      {'insert': ' 뒤\n'},
    ]);
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
  });

  test('발췌 메모는 현재 문장과 분리하고 모든 줄을 인용으로 삽입한다', () {
    final controller = QuillController(
      document: Document.fromJson([
        {'insert': '앞뒤\n'},
      ]),
      selection: const TextSelection.collapsed(offset: 1),
    );
    addTearDown(controller.dispose);

    service.insert(
      controller,
      _memo(type: BookNoteMemoType.quote, content: '첫 줄\n::hl[[둘째 줄]]'),
    );

    expect(controller.document.toPlainText(), '앞\n첫 줄\n둘째 줄\n뒤\n');
    final ops = controller.document.toDelta().toJson();
    final quotedNewlines = ops.where(
      (op) =>
          op['insert'] == '\n' &&
          (op['attributes'] as Map?)?['blockquote'] == true,
    );
    expect(quotedNewlines, hasLength(2));
    expect(
      ops,
      contains(
        isA<Map<String, dynamic>>()
            .having((op) => op['insert'], 'insert', '둘째 줄')
            .having(
              (op) => (op['attributes'] as Map?)?['background'],
              'background',
              BookReflectionMemoInsertService.highlightColorValue,
            ),
      ),
    );
  });
}

BookNoteMemo _memo({required BookNoteMemoType type, required String content}) {
  final now = DateTime(2026, 8, 21);
  return BookNoteMemo(
    id: 1,
    serverId: 1,
    clientRequestId: null,
    noteId: 1,
    type: type,
    startPage: null,
    endPage: null,
    content: content,
    imageUrl: null,
    isImportant: content.contains('::hl[['),
    sortOrder: 0,
    deletedAt: null,
    createdAt: now,
    updatedAt: now,
    isDirty: false,
  );
}
