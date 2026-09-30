import 'dart:developer' as developer;

import '../../bookshelf/models/book_item.dart';
import '../../record_archive/data/record_archive_dao.dart';
import '../../record_archive/models/record_archive.dart';
import '../../server_storage_migration/data/record_import_snapshot.dart';
import '../../server_storage_migration/data/record_import_validation.dart';
import '../../server_storage_migration/models/record_import_models.dart';
import '../models/external_import_models.dart';
import 'external_import_snapshot_builder.dart';

/// 동기화가 꺼져 있거나 계정 없이 쓰는 경우의 외부 기록 가져오기. 서버를
/// 거치지 않고 내 기록(ZIP) 가져오기와 같은 [RecordArchiveDao.restore]로
/// 로컬 DB에 한 트랜잭션으로 저장한다. 나중에 동기화를 켜면 기존 동기화
/// 켜기(서버 Import)가 함께 올린다. 동기화가 켜진 경우는 서버 Import를 먼저
/// 거치는 [ExternalRecordImportService]를 쓴다.
class ExternalRecordLocalImportService {
  const ExternalRecordLocalImportService({
    required this.dao,
    this.snapshotBuilder = const ExternalImportSnapshotBuilder(),
  });

  final RecordArchiveDao dao;
  final ExternalImportSnapshotBuilder snapshotBuilder;

  Future<void> run(
    ExternalImportParseResult input, {
    required int ownerUserId,
    required bool Function() sessionValid,
    Map<String, BookItem> existingBooksByIsbn = const {},
    Set<String> overwriteExistingIsbns = const {},
  }) async {
    if (input.books.isEmpty) {
      throw const ExternalImportException(
        '가져올 수 있는 책 기록이 없어요.',
        reason: 'no_importable_books',
      );
    }
    final snapshot = snapshotBuilder.build(
      input,
      existingBooksByIsbn: existingBooksByIsbn,
      overwriteExistingIsbns: overwriteExistingIsbns,
    );
    // 나중에 동기화를 켜면 같은 규칙의 서버 Import로 올라간다. 여기서
    // 걸러내지 않으면 로컬에는 저장되지만 동기화 켜기가 실패하는 기록이 남는다.
    final validation = validateRecordImportSnapshot(
      books: snapshot.books,
      notes: snapshot.notes,
      memos: snapshot.noteMemos,
      reflections: snapshot.reflections,
      tags: snapshot.tags,
      tagMaps: snapshot.tagMaps,
    );
    if (validation != null) {
      developer.log(
        '[외부 기록 로컬 가져오기 준비] source=${input.source.code} '
        '${_countLog(snapshot.counts)} result=FAIL '
        'reason=import_preflight_failed validation="$validation"',
      );
      throw ExternalImportException(
        validation,
        reason: 'import_preflight_failed',
      );
    }

    final archive = _toArchive(snapshot);
    try {
      await dao.restore(
        archive.records,
        ownerUserId,
        const {},
        remoteCoverUrls: archive.remoteCoverUrls,
        allowedIsbnMatches: overwriteExistingIsbns,
        sessionValid: sessionValid,
      );
    } on ArchiveException catch (error) {
      developer.log(
        '[외부 기록 로컬 가져오기] source=${input.source.code} '
        '${_countLog(snapshot.counts)} result=FAIL reason=local_restore_failed',
      );
      throw ExternalImportException(
        error.message,
        reason: 'local_restore_failed',
      );
    }
    developer.log(
      '[외부 기록 가져오기] source=${input.source.code} '
      '${_countLog(snapshot.counts)} '
      'overwriteCount=${overwriteExistingIsbns.length} result=SUCCESS',
    );
  }

  /// 스냅샷을 로컬 복원 규격으로 옮긴다. 값은 DB 컬럼 형식을 그대로 쓴다.
  /// `categoryCode`는 넣지 않아, 덮어쓰기 대상 책의 기존 카테고리를 유지한다.
  ({RecordArchive records, Map<String, String> remoteCoverUrls}) _toArchive(
    RecordImportSnapshot snapshot,
  ) {
    final bookIds = <int, String>{};
    final noteIds = <int, String>{};
    final remoteCovers = <String, String>{};
    final books = <ArchiveRecord>[];
    for (final book in snapshot.books) {
      final id = book.clientRequestId!;
      bookIds[book.userBookId] = id;
      final cover = snapshot.coverImageUrlByBook[book.userBookId];
      if (cover != null) remoteCovers[id] = cover;
      books.add(
        ArchiveRecord(
          id: id,
          values: {
            'title': book.title,
            'author': book.author,
            'publisher': book.publisher,
            'isbn13': book.isbn13,
            'category': book.category,
            'statsTotalPages': book.statsTotalPages,
            'displayTotalPages': book.displayTotalPages,
            'status': book.status.apiValue,
            'currentPage': book.currentPage,
            'myRating': book.myRating,
            'shortReview': book.shortReview,
            'isMasterpiece': book.isMasterpiece,
            'wantToReread': book.wantToReread,
            'rereadCount': book.rereadCount,
            'difficulty': book.difficulty,
            'sourceType': book.sourceType,
            'platformName': book.platformName,
            'discoverySource': book.discoverySource,
            'startedAt': _date(book.startedAt),
            'finishedAt': _date(book.finishedAt),
            'libraryDueAt': _date(book.libraryDueAt),
            'createdAt': book.createdAt.toIso8601String(),
            'updatedAt': book.updatedAt.toIso8601String(),
            'coverImage': null,
            // 외부 서비스 태그는 가져오지 않는다. 기존 책 태그는 그대로 둔다.
            'tags': const <String>[],
          },
        ),
      );
    }
    final notes = <ArchiveRecord>[];
    for (final note in snapshot.notes) {
      final bookId = bookIds[note.userBookId]!;
      final id = '$bookId-note';
      noteIds[note.id] = id;
      notes.add(
        ArchiveRecord(
          id: id,
          values: {
            'bookId': bookId,
            'title': note.title,
            'createdAt': note.createdAt.toIso8601String(),
            'updatedAt': note.updatedAt.toIso8601String(),
          },
        ),
      );
    }
    final memos = [
      for (final memo in snapshot.noteMemos)
        ArchiveRecord(
          id: memo.clientRequestId!,
          values: {
            'noteId': noteIds[memo.noteId],
            'type': memo.type.dbValue,
            'startPage': memo.startPage,
            'endPage': memo.endPage,
            'content': memo.content,
            'image': null,
            'isImportant': memo.isImportant,
            'sortOrder': memo.sortOrder,
            'createdAt': memo.createdAt.toIso8601String(),
            'updatedAt': memo.updatedAt.toIso8601String(),
          },
        ),
    ];
    return (
      records: RecordArchive(
        exportedAt: DateTime.now().toUtc().toIso8601String(),
        books: books,
        notes: notes,
        memos: memos,
        reflections: const [],
        tags: const [],
      ),
      remoteCoverUrls: remoteCovers,
    );
  }

  String? _date(DateTime? value) => value?.toIso8601String().substring(0, 10);

  String _countLog(RecordImportCounts counts) {
    return 'bookCount=${counts.bookCount} '
        'noteCount=${counts.noteCount} '
        'noteMemoCount=${counts.noteMemoCount}';
  }
}
