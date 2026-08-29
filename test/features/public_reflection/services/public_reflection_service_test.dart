import 'package:bbbook/core/network/api_exception.dart';
import 'package:bbbook/features/public_reflection/data/public_reflection_source.dart';
import 'package:bbbook/features/public_reflection/models/public_reflection.dart';
import 'package:bbbook/features/public_reflection/services/public_reflection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const isbn13 = '9781234567890';

  test('목록에서 숨김 독후감을 제거하고 공개 항목만 반환한다', () async {
    final source = _FakePublicReflectionSource(
      pages: [
        PublicReflectionsPage(
          items: [_summary(id: 3, isHidden: true), _summary(id: 2)],
          nextCursor: null,
          hasNext: false,
        ),
      ],
    );

    final page = await PublicReflectionService(source).getPage(isbn13: isbn13);

    expect(page.items.map((item) => item.id), [2]);
    expect(page.items.every((item) => !item.isHidden), isTrue);
  });

  test('공개 항목이 요청 크기에 찰 때까지 다음 커서를 이어서 조회한다', () async {
    final source = _FakePublicReflectionSource(
      pages: [
        PublicReflectionsPage(
          items: [_summary(id: 5, isHidden: true)],
          nextCursor: 5,
          hasNext: true,
        ),
        PublicReflectionsPage(
          items: [_summary(id: 4)],
          nextCursor: 4,
          hasNext: true,
        ),
        PublicReflectionsPage(
          items: [_summary(id: 3)],
          nextCursor: null,
          hasNext: false,
        ),
      ],
    );

    final page = await PublicReflectionService(
      source,
    ).getPage(isbn13: isbn13, size: 2);

    expect(source.pageCursors, [null, 5, 4]);
    expect(source.pageSizes, [2, 2, 2]);
    expect(page.items.map((item) => item.id), [4, 3]);
    expect(page.nextCursor, isNull);
    expect(page.hasNext, isFalse);
  });

  test('다음 페이지가 있는데 커서가 없으면 잘못된 응답으로 거부한다', () async {
    final source = _FakePublicReflectionSource(
      pages: [
        PublicReflectionsPage(
          items: [_summary(id: 1)],
          nextCursor: null,
          hasNext: true,
        ),
      ],
    );

    await expectLater(
      PublicReflectionService(source).getPage(isbn13: isbn13),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '서버 응답을 처리할 수 없습니다.',
        ),
      ),
    );
  });

  test('상세 API가 판정한 접근 오류를 그대로 전달한다', () async {
    const error = ApiException('독후감을 찾을 수 없습니다.', statusCode: 404);
    final source = _FakePublicReflectionSource(detailError: error);

    await expectLater(
      PublicReflectionService(
        source,
      ).getDetail(isbn13: isbn13, reflectionId: 7),
      throwsA(same(error)),
    );
  });

  test('공개·발행·동일 ISBN 상세의 Quill contentJson을 변경 없이 반환한다', () async {
    final detail = _detail();
    final source = _FakePublicReflectionSource(detail: detail);

    final result = await PublicReflectionService(
      source,
    ).getDetail(isbn13: isbn13, reflectionId: detail.id);

    expect(result, same(detail));
    expect(result.contentJson, {
      'ops': [
        {
          'insert': '헤더',
          'attributes': {'color': '#0061A3'},
        },
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {
          'insert': {'image': 'https://example.test/image.jpg'},
        },
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
      ],
    });
  });

  test('flat 작성자 형식의 상세 응답도 정규화해 리더에 반환한다', () async {
    final detail = PublicReflectionDetail.fromJson({
      'id': 8,
      'isbn13': isbn13,
      'book': {'title': '책', 'author': null, 'coverImageUrl': null},
      'title': '독후감',
      'contentJson': {
        'ops': [
          {'insert': '본문\n'},
        ],
      },
      'contentText': '본문',
      'isPublic': true,
      'status': 'PUBLISHED',
      'userId': 21,
      'nickname': 'flat 작성자',
      'profileImageUrl': 'https://example.test/profile.jpg',
      'createdAt': '2026-08-28T00:00:00Z',
      'updatedAt': '2026-08-28T00:00:00Z',
    });
    final source = _FakePublicReflectionSource(detail: detail);

    final result = await PublicReflectionService(
      source,
    ).getDetail(isbn13: isbn13, reflectionId: detail.id);

    expect(result.user.id, 21);
    expect(result.user.nickname, 'flat 작성자');
    expect(result.user.profileImageUrl, 'https://example.test/profile.jpg');
  });

  test('레거시 상세에 status가 없더라도 공개 글이면 리더에 반환한다', () async {
    final detail = _detail(status: '');
    final source = _FakePublicReflectionSource(detail: detail);

    final result = await PublicReflectionService(
      source,
    ).getDetail(isbn13: isbn13, reflectionId: detail.id);

    expect(result, same(detail));
  });

  test('ISBN 하이픈 표기만 다른 공개 상세를 같은 책으로 처리한다', () async {
    final detail = _detail(isbn13: '978-1-234-56789-0');
    final source = _FakePublicReflectionSource(detail: detail);

    final result = await PublicReflectionService(
      source,
    ).getDetail(isbn13: isbn13, reflectionId: detail.id);

    expect(result, same(detail));
  });
}

PublicReflectionSummary _summary({required int id, bool isHidden = false}) {
  return PublicReflectionSummary(
    id: id,
    title: isHidden ? null : '독후감 $id',
    contentText: isHidden ? null : '본문 $id',
    isHidden: isHidden,
    user: const PublicReflectionAuthor(id: 10, nickname: '독자'),
    createdAt: DateTime.utc(2026, 8, 28),
    updatedAt: DateTime.utc(2026, 8, 28),
  );
}

PublicReflectionDetail _detail({
  String isbn13 = '9781234567890',
  bool isPublic = true,
  String status = 'PUBLISHED',
}) {
  return PublicReflectionDetail(
    id: 7,
    isbn13: isbn13,
    book: const PublicReflectionBook(title: '책'),
    title: '긴 독후감',
    contentJson: const {
      'ops': [
        {
          'insert': '헤더',
          'attributes': {'color': '#0061A3'},
        },
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {
          'insert': {'image': 'https://example.test/image.jpg'},
        },
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
      ],
    },
    contentText: '헤더',
    isPublic: isPublic,
    status: status,
    user: const PublicReflectionAuthor(id: 10, nickname: '독자'),
    createdAt: DateTime.utc(2026, 8, 28),
    updatedAt: DateTime.utc(2026, 8, 28),
  );
}

class _FakePublicReflectionSource implements PublicReflectionSource {
  _FakePublicReflectionSource({
    this.pages = const [],
    this.detail,
    this.detailError,
  });

  final List<PublicReflectionsPage> pages;
  final PublicReflectionDetail? detail;
  final Object? detailError;
  final List<int?> pageCursors = [];
  final List<int> pageSizes = [];
  var _pageIndex = 0;

  @override
  Future<int> deleteLike(int reflectionId) {
    throw UnimplementedError();
  }

  @override
  Future<PublicReflectionDetail> fetchDetail(int reflectionId) async {
    if (detailError case final error?) throw error;
    return detail!;
  }

  @override
  Future<PublicReflectionsPage> fetchPage({
    required String isbn13,
    int? cursor,
    required int size,
  }) async {
    pageCursors.add(cursor);
    pageSizes.add(size);
    return pages[_pageIndex++];
  }

  @override
  Future<int> postLike(int reflectionId) {
    throw UnimplementedError();
  }
}
