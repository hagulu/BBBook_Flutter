import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/bookshelf/models/book_tag.dart';
import 'package:flutter_test/flutter_test.dart';

/// 로컬 저장 모드의 책 정보 수정·ISBN 연결이 쓰는 병합 규칙 테스트.
///
/// 서버 응답으로 행 전체를 갈아끼우던 자리를 로컬 병합이 대신하므로,
/// 여기서 필드를 하나라도 흘리면 읽는 중 상태·평점·날짜 같은 기록이
/// 조용히 사라진다.
void main() {
  final now = DateTime.utc(2026, 8, 24);
  final book = BookItem(
    userBookId: -1,
    serverId: 10,
    clientRequestId: 'req-1',
    bookId: 77,
    isbn13: '9788900000000',
    title: '옛 제목',
    author: '옛 저자',
    publisher: '옛 출판사',
    statsTotalPages: 300,
    displayTotalPages: null,
    coverImageUrl: 'https://cdn.example.com/old.jpg',
    displayCategoryId: 3,
    category: '소설',
    status: BookStatus.reading,
    currentPage: 120,
    myRating: 4.5,
    shortReview: '좋았다',
    isMasterpiece: true,
    sourceType: 'PAPER',
    rereadCount: 2,
    difficulty: 'NORMAL',
    startedAt: DateTime.utc(2026, 8, 1),
    finishedAt: null,
    platformName: '교보',
    discoverySource: '추천',
    tags: const [BookTag(id: 1, name: '에세이')],
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 8, 20),
  );

  test('책 정보만 바꾸고 읽기 기록·태그·식별자는 그대로 둔다', () {
    final updated = book.copyWithBookInfo(
      title: '새 제목',
      author: null,
      publisher: '새 출판사',
      statsTotalPages: 320,
      displayTotalPages: null,
      displayCategoryId: 5,
      category: null,
      coverImageUrl: 'book_covers/local_1.jpg',
      isbn13: book.isbn13,
      bookId: book.bookId,
      updatedAt: now,
    );

    expect(updated.title, '새 제목');
    // 넘긴 값이 곧 새 값이다 — null도 "지움"으로 반영한다.
    expect(updated.author, isNull);
    expect(updated.publisher, '새 출판사');
    expect(updated.statsTotalPages, 320);
    expect(updated.displayCategoryId, 5);
    expect(updated.coverImageUrl, 'book_covers/local_1.jpg');
    expect(updated.updatedAt, now);

    // 기록·식별자는 손대지 않는다.
    expect(updated.userBookId, book.userBookId);
    expect(updated.serverId, book.serverId);
    expect(updated.clientRequestId, book.clientRequestId);
    expect(updated.status, book.status);
    expect(updated.currentPage, 120);
    expect(updated.myRating, 4.5);
    expect(updated.shortReview, '좋았다');
    expect(updated.isMasterpiece, isTrue);
    expect(updated.rereadCount, 2);
    expect(updated.difficulty, 'NORMAL');
    expect(updated.startedAt, book.startedAt);
    expect(updated.platformName, '교보');
    expect(updated.discoverySource, '추천');
    expect(updated.tags, book.tags);
    expect(updated.createdAt, book.createdAt);
  });

  test('ISBN 연결 해제는 식별자만 비운다', () {
    final unlinked = book.copyWithBookInfo(
      title: book.title,
      author: book.author,
      publisher: book.publisher,
      statsTotalPages: book.statsTotalPages,
      displayTotalPages: book.displayTotalPages,
      displayCategoryId: book.displayCategoryId,
      category: book.category,
      coverImageUrl: book.coverImageUrl,
      isbn13: null,
      bookId: null,
      updatedAt: now,
    );

    expect(unlinked.isbn13, isNull);
    expect(unlinked.bookId, isNull);
    // 표시 정보는 연결 해제 후에도 남는다(서버 정책과 동일).
    expect(unlinked.title, '옛 제목');
    expect(unlinked.coverImageUrl, 'https://cdn.example.com/old.jpg');
  });
}
