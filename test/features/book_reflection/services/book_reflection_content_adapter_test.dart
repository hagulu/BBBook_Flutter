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

  group('본문 이미지 추출·치환', () {
    test('Delta 본문의 이미지를 등장 순서대로 모은다', () {
      final sources = adapter.imageSources({
        'ops': [
          {'insert': '앞 문장'},
          {
            'insert': {'image': 'reflection_images/local_1.jpg'},
            'attributes': {'width': '280.0'},
          },
          {'insert': '\n'},
          {
            'insert': {'image': 'https://cdn.example.com/r/a.jpg'},
          },
          {'insert': '\n'},
        ],
      });

      expect(sources, [
        'reflection_images/local_1.jpg',
        'https://cdn.example.com/r/a.jpg',
      ]);
    });

    test('레거시 Tiptap 본문의 중첩된 이미지도 찾는다', () {
      final sources = adapter.imageSources({
        'type': 'doc',
        'content': [
          {
            'type': 'paragraph',
            'content': [
              {
                'type': 'image',
                'attrs': {'src': 'https://cdn.example.com/r/inline.jpg'},
              },
            ],
          },
          {
            'type': 'image',
            'attrs': {'src': 'reflection_images/local_2.png'},
          },
        ],
      });

      expect(sources, [
        'https://cdn.example.com/r/inline.jpg',
        'reflection_images/local_2.png',
      ]);
    });

    test('이미지 출처만 바꾸고 크기 같은 속성은 유지한다', () {
      final replaced = adapter.replaceImageSources(
        {
          'ops': [
            {
              'insert': {'image': 'reflection_images/local_1.jpg'},
              'attributes': {'width': '280.0'},
            },
            {
              'insert': {'image': 'https://cdn.example.com/r/keep.jpg'},
            },
            {'insert': '\n'},
          ],
        },
        {'reflection_images/local_1.jpg': 'https://cdn.example.com/temp/1.jpg'},
      );

      final ops = replaced['ops'] as List<dynamic>;
      expect((ops.first as Map)['insert'], {
        'image': 'https://cdn.example.com/temp/1.jpg',
      });
      expect((ops.first as Map)['attributes'], {'width': '280.0'});
      // 치환 대상이 아닌 이미지는 그대로다.
      expect((ops[1] as Map)['insert'], {
        'image': 'https://cdn.example.com/r/keep.jpg',
      });
      expect(adapter.imageSources(replaced), [
        'https://cdn.example.com/temp/1.jpg',
        'https://cdn.example.com/r/keep.jpg',
      ]);
    });

    test('Tiptap 본문 치환도 다른 attrs를 지우지 않는다', () {
      final replaced = adapter.replaceImageSources(
        {
          'type': 'doc',
          'content': [
            {
              'type': 'image',
              'attrs': {'src': 'reflection_images/local_2.png', 'width': 320},
            },
          ],
        },
        {'reflection_images/local_2.png': 'https://cdn.example.com/temp/2.png'},
      );

      final node = (replaced['content'] as List<dynamic>).single as Map;
      expect(node['attrs'], {
        'src': 'https://cdn.example.com/temp/2.png',
        'width': 320,
      });
    });

    test('치환할 항목이 없으면 본문을 그대로 둔다', () {
      final json = {
        'ops': [
          {'insert': '이미지 없음\n'},
        ],
      };

      expect(adapter.replaceImageSources(json, const {}), same(json));
      expect(adapter.imageSources(json), isEmpty);
      expect(adapter.imageSources(null), isEmpty);
    });
  });
}
