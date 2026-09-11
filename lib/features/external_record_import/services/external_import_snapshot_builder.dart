import 'package:uuid/uuid.dart';

import '../../book_note/models/book_note.dart';
import '../../bookshelf/models/book_item.dart';
import '../../server_storage_migration/data/record_import_snapshot.dart';
import '../../tag/models/tag_mapping.dart';
import '../models/external_import_models.dart';

class ExternalImportSnapshotBuilder {
  const ExternalImportSnapshotBuilder({this.uuid = const Uuid()});

  final Uuid uuid;

  RecordImportSnapshot build(
    ExternalImportParseResult input, {
    Map<String, BookItem> existingBooksByIsbn = const {},
    Set<String> overwriteExistingIsbns = const {},
  }) {
    final now = DateTime.now().toUtc();
    final books = <BookItem>[];
    final notes = <BookNote>[];
    final memos = <BookNoteMemo>[];
    final tagsByName = <String, LocalTag>{};
    final tagMaps = <TagMapping>[];
    final covers = <int, String>{};
    var noteLocalId = -1000001;
    var memoLocalId = -2000001;
    var tagLocalId = -3000001;
    var tagMapLocalId = -4000001;

    for (var bookIndex = 0; bookIndex < input.books.length; bookIndex++) {
      final external = input.books[bookIndex];
      final bookLocalId = -(bookIndex + 1);
      final identity = _bookIdentity(external);
      final createdAt = external.createdAt ?? now;
      final isEbook = external.sourceType == ExternalBookSourceType.ebook;
      final isAudio = external.sourceType == ExternalBookSourceType.audioBook;
      final isbn13 = external.isbn13;
      final existing = isbn13 == null ? null : existingBooksByIsbn[isbn13];
      final overwriteExisting =
          existing != null &&
          isbn13 != null &&
          overwriteExistingIsbns.contains(isbn13);
      final book = existing == null || overwriteExisting
          ? BookItem(
              userBookId: bookLocalId,
              serverId: overwriteExisting ? existing.serverId : null,
              // 같은 clientRequestId의 활성 책은 서버가 기존 필드를 유지한다.
              // 사용자가 명시적으로 덮어쓰기를 선택한 경우에는 새 키를 써서
              // serverId/ISBN 매칭의 교체 정책을 타게 한다.
              clientRequestId: overwriteExisting
                  ? uuid.v4()
                  : _stableId('book|$identity'),
              isbn13: external.isbn13,
              title: external.title,
              author: external.author,
              publisher: external.publisher,
              statsTotalPages: isEbook || isAudio ? null : external.totalPages,
              displayTotalPages: isEbook ? external.totalPages : null,
              coverImageUrl: external.coverImageUrl,
              displayCategoryId: existing?.displayCategoryId,
              category: existing?.category,
              status: external.status,
              currentPage: external.currentPage,
              myRating: external.rating,
              shortReview: external.shortReview,
              isMasterpiece: existing?.isMasterpiece ?? false,
              sourceType: external.sourceType?.apiValue,
              rereadCount: external.rereadCount,
              wantToReread: existing?.wantToReread ?? false,
              difficulty: existing?.difficulty,
              startedAt: external.startedAt,
              finishedAt: external.finishedAt,
              libraryId: existing?.libraryId,
              libraryDueAt: existing?.libraryDueAt,
              platformName: existing?.platformName,
              discoverySource: existing?.discoverySource,
              tags: existing?.tags ?? const [],
              createdAt: createdAt,
              updatedAt: createdAt,
            )
          : _preserveExistingBook(
              existing,
              localId: bookLocalId,
              fallbackClientRequestId: _stableId('book|$identity'),
            );
      books.add(book);
      if (existing == null && external.coverImageUrl != null) {
        covers[bookLocalId] = external.coverImageUrl!;
      }

      if (external.notes.isNotEmpty) {
        final parentNoteId = noteLocalId--;
        notes.add(
          BookNote(
            id: parentNoteId,
            serverId: null,
            userBookId: bookLocalId,
            title: '${external.source.label} 메모',
            deletedAt: null,
            createdAt: createdAt,
            updatedAt: createdAt,
            isDirty: true,
          ),
        );
        for (
          var memoIndex = 0;
          memoIndex < external.notes.length;
          memoIndex++
        ) {
          final externalMemo = external.notes[memoIndex];
          final memoCreatedAt = externalMemo.createdAt ?? createdAt;
          final memoIdentity =
              externalMemo.sourceNoteId ?? '$memoIndex|${externalMemo.content}';
          memos.add(
            BookNoteMemo(
              id: memoLocalId--,
              serverId: null,
              clientRequestId: _stableId('memo|$identity|$memoIdentity'),
              noteId: parentNoteId,
              type: _memoType(externalMemo.type),
              startPage: externalMemo.startPage,
              endPage: externalMemo.endPage,
              content: externalMemo.content,
              imageUrl: null,
              localImagePath: null,
              isImportant: false,
              sortOrder: memoIndex,
              deletedAt: null,
              createdAt: memoCreatedAt,
              updatedAt: memoCreatedAt,
              isDirty: true,
            ),
          );
        }
      }

      for (final tagName in external.tags) {
        final tag = tagsByName.putIfAbsent(
          tagName,
          () => LocalTag(id: tagLocalId--, serverId: null, name: tagName),
        );
        tagMaps.add(
          TagMapping(
            id: tagMapLocalId--,
            serverId: null,
            userBookId: bookLocalId,
            tagId: tag.id,
            deletedAt: null,
            createdAt: createdAt,
            updatedAt: createdAt,
            isDirty: true,
          ),
        );
      }
    }

    return RecordImportSnapshot(
      books: books,
      tags: tagsByName.values.toList(growable: false),
      notes: notes,
      noteMemos: memos,
      reflections: const [],
      tagMaps: tagMaps,
      coverImageUrlByBook: covers,
      pendingMemoImages: const {},
      pendingReflectionImages: const {},
    );
  }

  String _bookIdentity(ExternalBookImportItem book) {
    final sourceId = book.sourceBookId?.trim();
    if (sourceId != null && sourceId.isNotEmpty) {
      return '${book.source.code}|$sourceId';
    }
    final isbn = book.isbn13;
    if (isbn != null) return '${book.source.code}|isbn|$isbn';
    return [
      book.source.code,
      book.title.trim().toLowerCase(),
      book.author?.trim().toLowerCase() ?? '',
      book.publisher?.trim().toLowerCase() ?? '',
    ].join('|');
  }

  String _stableId(String value) => uuid.v5(Namespace.url.value, value);

  BookItem _preserveExistingBook(
    BookItem existing, {
    required int localId,
    required String fallbackClientRequestId,
  }) {
    return BookItem(
      userBookId: localId,
      serverId: existing.serverId,
      clientRequestId: existing.clientRequestId ?? fallbackClientRequestId,
      bookId: existing.bookId,
      isbn13: existing.isbn13,
      title: existing.title,
      author: existing.author,
      publisher: existing.publisher,
      statsTotalPages: existing.statsTotalPages,
      displayTotalPages: existing.displayTotalPages,
      coverImageUrl: existing.coverImageUrl,
      displayCategoryId: existing.displayCategoryId,
      category: existing.category,
      status: existing.status,
      currentPage: existing.currentPage,
      myRating: existing.myRating,
      shortReview: existing.shortReview,
      isMasterpiece: existing.isMasterpiece,
      sourceType: existing.sourceType,
      rereadCount: existing.rereadCount,
      wantToReread: existing.wantToReread,
      difficulty: existing.difficulty,
      startedAt: existing.startedAt,
      finishedAt: existing.finishedAt,
      libraryId: existing.libraryId,
      libraryDueAt: existing.libraryDueAt,
      platformName: existing.platformName,
      discoverySource: existing.discoverySource,
      tags: existing.tags,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt,
    );
  }

  BookNoteMemoType _memoType(ExternalNoteType type) => switch (type) {
    ExternalNoteType.summary => BookNoteMemoType.summary,
    ExternalNoteType.quote => BookNoteMemoType.quote,
    ExternalNoteType.thought => BookNoteMemoType.thought,
  };
}
