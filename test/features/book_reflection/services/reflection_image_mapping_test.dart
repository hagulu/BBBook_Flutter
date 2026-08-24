import 'package:bbbook/features/book_reflection/services/reflection_image_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

/// push 응답과 로컬 사본을 짝짓는 규칙 테스트.
///
/// 여기서 틀리면 방금 업로드한 이미지의 로컬 사본이 본문과 연결되지 않아
/// (화면은 서버에서 다시 받고, 정리는 그 파일을 지운다) 곧바로 재다운로드가
/// 발생하거나, 반대로 엉뚱한 URL에 남의 사본이 붙는다.
void main() {
  test('업로드한 로컬 이미지는 응답 URL과 짝지어 매칭된다', () {
    final mappings = resolveReflectionImageMappings(
      documentSources: const [
        'reflection_images/local_1.jpg',
        'https://cdn.example.com/r/keep.jpg',
      ],
      responseSources: const [
        'https://cdn.example.com/temp/new.jpg',
        'https://cdn.example.com/r/keep.jpg',
      ],
      localImagePathBySource: const {
        'reflection_images/local_1.jpg': 'reflection_images/local_1.jpg',
        'https://cdn.example.com/r/keep.jpg':
            'reflection_images/remote_keep.jpg',
      },
    );

    expect(mappings, {
      'https://cdn.example.com/temp/new.jpg': 'reflection_images/local_1.jpg',
      'https://cdn.example.com/r/keep.jpg': 'reflection_images/remote_keep.jpg',
    });
  });

  test('서버가 URL을 바꿔 돌려줘도 순서로 로컬 사본을 이어받는다', () {
    // 임시 업로드 URL을 서버가 영구 경로로 옮겨 응답하는 경우.
    final mappings = resolveReflectionImageMappings(
      documentSources: const ['https://cdn.example.com/temp/a.jpg'],
      responseSources: const ['https://cdn.example.com/reflections/9/a.jpg'],
      localImagePathBySource: const {
        'https://cdn.example.com/temp/a.jpg': 'reflection_images/local_1.jpg',
      },
    );

    expect(mappings, {
      'https://cdn.example.com/reflections/9/a.jpg':
          'reflection_images/local_1.jpg',
    });
  });

  test('로컬 사본을 모르는 이미지는 매칭하지 않는다', () {
    final mappings = resolveReflectionImageMappings(
      documentSources: const ['https://cdn.example.com/r/only-remote.jpg'],
      responseSources: const ['https://cdn.example.com/r/only-remote.jpg'],
      localImagePathBySource: const {},
    );

    // 매칭이 없으면 hydration이 나중에 내려받아 채운다.
    expect(mappings, isEmpty);
  });

  test('본문과 응답의 이미지 개수가 다르면 순서를 믿지 않는다', () {
    final mappings = resolveReflectionImageMappings(
      documentSources: const [
        'reflection_images/local_1.jpg',
        'reflection_images/local_2.jpg',
      ],
      responseSources: const ['https://cdn.example.com/temp/new.jpg'],
      localImagePathBySource: const {
        'reflection_images/local_1.jpg': 'reflection_images/local_1.jpg',
        'reflection_images/local_2.jpg': 'reflection_images/local_2.jpg',
      },
    );

    expect(mappings, isEmpty);
  });

  test('같은 이미지를 두 번 넣어도 매칭은 하나로 모인다', () {
    final mappings = resolveReflectionImageMappings(
      documentSources: const [
        'reflection_images/local_1.jpg',
        'reflection_images/local_1.jpg',
      ],
      responseSources: const [
        'https://cdn.example.com/temp/new.jpg',
        'https://cdn.example.com/temp/new.jpg',
      ],
      localImagePathBySource: const {
        'reflection_images/local_1.jpg': 'reflection_images/local_1.jpg',
      },
    );

    expect(mappings, hasLength(1));
  });
}
