import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/external_record_import/models/external_import_models.dart';
import 'package:bbbook/features/external_record_import/services/external_import_snapshot_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = ExternalImportSnapshotBuilder();

  ExternalImportParseResult input() => ExternalImportParseResult(
    source: ExternalImportSource.bookmory,
    discoveredBookCount: 1,
    skippedItemCount: 0,
    warningCount: 0,
    books: [
      ExternalBookImportItem(
        source: ExternalImportSource.bookmory,
        sourceBookId: 'source-1',
        isbn13: '9781234567890',
        title: '책',
        status: BookStatus.reading,
        currentPage: 25,
        totalPages: 100,
        rereadCount: 1,
        sourceType: ExternalBookSourceType.ebook,
        notes: [
          ExternalNoteImportItem(
            type: ExternalNoteType.quote,
            sourceNoteId: 'note-1',
            content: '내용',
          ),
        ],
        tags: ['태그'],
      ),
    ],
  );

  test('공통 모델을 기존 Import 스냅샷 관계로 변환한다', () {
    final snapshot = builder.build(input());
    expect(snapshot.books, hasLength(1));
    expect(snapshot.books.single.statsTotalPages, isNull);
    expect(snapshot.books.single.displayTotalPages, 100);
    expect(snapshot.books.single.rereadCount, 1);
    expect(snapshot.notes, hasLength(1));
    expect(snapshot.noteMemos, hasLength(1));
    expect(snapshot.noteMemos.single.noteId, snapshot.notes.single.id);
    expect(snapshot.tags.single.name, '태그');
    expect(
      snapshot.tagMaps.single.userBookId,
      snapshot.books.single.userBookId,
    );
    expect(snapshot.counts.bookCount, 1);
    expect(snapshot.counts.noteMemoCount, 1);
  });

  test('같은 외부 항목은 재가져오기에도 같은 멱등 키를 사용한다', () {
    final first = builder.build(input());
    final second = builder.build(input());
    expect(
      first.books.single.clientRequestId,
      second.books.single.clientRequestId,
    );
    expect(
      first.noteMemos.single.clientRequestId,
      second.noteMemos.single.clientRequestId,
    );
  });

  test('동일 ISBN의 기존 책은 기록과 설정을 보존하고 메모만 연결한다', () {
    final createdAt = DateTime.utc(2026, 1, 1);
    final updatedAt = DateTime.utc(2026, 9, 1);
    final existing = BookItem(
      userBookId: 91,
      serverId: 901,
      clientRequestId: '11111111-1111-1111-1111-111111111111',
      bookId: 81,
      isbn13: '9781234567890',
      title: '기존 제목',
      author: '기존 저자',
      publisher: '기존 출판사',
      statsTotalPages: 320,
      displayTotalPages: 300,
      coverImageUrl: '/local/cached-cover.webp',
      displayCategoryId: 7,
      category: '인문',
      status: BookStatus.finished,
      currentPage: 300,
      myRating: 5,
      shortReview: '기존 한줄평',
      isMasterpiece: true,
      sourceType: 'PAPER_BOOK',
      rereadCount: 3,
      wantToReread: true,
      difficulty: 'HARD',
      startedAt: DateTime(2026, 8, 1),
      finishedAt: DateTime(2026, 8, 31),
      libraryId: 12,
      libraryDueAt: DateTime(2026, 9, 20),
      platformName: '도서관',
      discoverySource: 'FRIEND',
      tags: const [],
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final snapshot = builder.build(
      input(),
      existingBooksByIsbn: {'9781234567890': existing},
    );
    final preserved = snapshot.books.single;

    expect(preserved.userBookId, -1);
    expect(preserved.serverId, existing.serverId);
    expect(preserved.clientRequestId, existing.clientRequestId);
    expect(preserved.title, existing.title);
    expect(preserved.status, existing.status);
    expect(preserved.currentPage, existing.currentPage);
    expect(preserved.myRating, existing.myRating);
    expect(preserved.isMasterpiece, isTrue);
    expect(preserved.displayCategoryId, existing.displayCategoryId);
    expect(preserved.wantToReread, isTrue);
    expect(preserved.difficulty, existing.difficulty);
    expect(preserved.libraryId, existing.libraryId);
    expect(preserved.platformName, existing.platformName);
    expect(snapshot.coverImageUrlByBook, isEmpty);
    expect(snapshot.noteMemos, hasLength(1));
  });

  test('같은 서지 정보의 북적북적 행도 인덱스로 서로 구분한다', () {
    final duplicatedBibliography = ExternalImportParseResult(
      source: ExternalImportSource.bookJuk,
      discoveredBookCount: 2,
      skippedItemCount: 0,
      warningCount: 0,
      books: const [
        ExternalBookImportItem(
          source: ExternalImportSource.bookJuk,
          sourceBookId: '10',
          title: '같은 책',
          author: '같은 저자',
          publisher: '같은 출판사',
          status: BookStatus.finished,
          currentPage: 0,
          rereadCount: 1,
          notes: [],
          tags: [],
        ),
        ExternalBookImportItem(
          source: ExternalImportSource.bookJuk,
          sourceBookId: '11',
          title: '같은 책',
          author: '같은 저자',
          publisher: '같은 출판사',
          status: BookStatus.reading,
          currentPage: 0,
          rereadCount: 0,
          notes: [],
          tags: [],
        ),
      ],
    );

    final snapshot = builder.build(duplicatedBibliography);

    expect(snapshot.books, hasLength(2));
    expect(
      snapshot.books.map((book) => book.clientRequestId).toSet(),
      hasLength(2),
    );
  });
}
