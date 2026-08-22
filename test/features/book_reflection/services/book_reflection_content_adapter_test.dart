import 'package:bbbook/features/book_reflection/services/book_reflection_content_adapter.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = BookReflectionContentAdapter();

  test('Quill Delta의 서식과 이미지가 저장 후 다시 복원된다', () {
    final original = Document.fromJson([
      {
        'insert': '서식 있는 문장',
        'attributes': {
          'bold': true,
          'italic': true,
          'color': '#112233',
          'background': '#ffeeaa',
        },
      },
      {
        'insert': '\n',
        'attributes': {'header': 1},
      },
      {
        'insert': {'image': 'https://example.com/reflection.webp'},
        'attributes': {'width': '280.0'},
      },
      {'insert': '\n'},
    ]);

    final serverJson = adapter.toServerJson(original);
    final restored = adapter.fromServerJson(serverJson);

    expect(restored.toDelta().toJson(), original.toDelta().toJson());
    expect(adapter.toContentText(restored), '서식 있는 문장');
  });

  test('레거시 Tiptap 문서를 Quill Delta로 변환한다', () {
    final document = adapter.fromServerJson({
      'type': 'doc',
      'content': [
        {
          'type': 'heading',
          'attrs': {'level': 2},
          'content': [
            {
              'type': 'text',
              'text': '제목',
              'marks': [
                {'type': 'bold'},
              ],
            },
          ],
        },
        {
          'type': 'blockquote',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {
                  'type': 'text',
                  'text': '인용',
                  'marks': [
                    {
                      'type': 'textStyle',
                      'attrs': {'color': '#123456'},
                    },
                    {
                      'type': 'highlight',
                      'attrs': {'color': '#abcdef'},
                    },
                  ],
                },
              ],
            },
          ],
        },
        {
          'type': 'bulletList',
          'content': [
            {
              'type': 'listItem',
              'content': [
                {
                  'type': 'paragraph',
                  'content': [
                    {'type': 'text', 'text': '항목'},
                  ],
                },
              ],
            },
          ],
        },
        {
          'type': 'image',
          'attrs': {'src': 'https://example.com/legacy.jpg', 'width': 420},
        },
      ],
    });

    expect(document.toDelta().toJson(), [
      {
        'insert': '제목',
        'attributes': {'bold': true},
      },
      {
        'insert': '\n',
        'attributes': {'header': 2},
      },
      {
        'insert': '인용',
        'attributes': {'color': '#123456', 'background': '#abcdef'},
      },
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
      {'insert': '항목'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
      {
        'insert': {'image': 'https://example.com/legacy.jpg'},
        'attributes': {'width': '420'},
      },
      {'insert': '\n'},
    ]);
    expect(adapter.toContentText(document), '제목\n인용\n항목');
  });

  test('contentText는 불필요한 마지막 개행만 제거한다', () {
    final document = Document.fromJson([
      {'insert': '첫 줄\n둘째 줄\n\n'},
    ]);

    expect(adapter.toContentText(document), '첫 줄\n둘째 줄');
  });
}
