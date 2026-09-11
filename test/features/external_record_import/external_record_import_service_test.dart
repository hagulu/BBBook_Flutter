import 'package:bbbook/features/book_note/models/book_note.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/external_record_import/models/external_import_models.dart';
import 'package:bbbook/features/external_record_import/providers/external_import_providers.dart';
import 'package:bbbook/features/external_record_import/services/external_record_import_service.dart';
import 'package:bbbook/features/server_storage_migration/models/record_import_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ExternalImportParseResult input() => const ExternalImportParseResult(
    source: ExternalImportSource.bookJuk,
    discoveredBookCount: 1,
    skippedItemCount: 0,
    warningCount: 0,
    books: [
      ExternalBookImportItem(
        source: ExternalImportSource.bookJuk,
        sourceBookId: '1',
        title: '책',
        status: BookStatus.finished,
        currentPage: 0,
        rereadCount: 1,
        notes: [],
        tags: [],
      ),
    ],
  );

  test('기존 Import 세션의 start/items/complete 순서로 저장한다', () async {
    final gateway = _FakeGateway();
    final progress = <ExternalImportProgress>[];
    await ExternalRecordImportService(
      api: gateway,
    ).run(input(), onProgress: progress.add);

    expect(gateway.calls, ['start', 'items:1', 'complete:1']);
    expect(gateway.completedCounts?.bookCount, 1);
    expect(progress.last.ratio, 1);
  });

  test('남아 있는 미완료 세션은 취소하고 새 세션으로 시작한다', () async {
    final gateway = _FakeGateway(firstImportedCount: 2);
    await ExternalRecordImportService(api: gateway).run(input());

    expect(gateway.calls, [
      'start',
      'cancel:1',
      'start',
      'items:2',
      'complete:2',
    ]);
  });

  test('업로드 실패는 서버 자동 롤백에 맡기고 추가 취소하지 않는다', () async {
    final gateway = _FakeGateway(failUpload: true);
    await expectLater(
      () => ExternalRecordImportService(api: gateway).run(input()),
      throwsA(isA<ExternalImportException>()),
    );
    expect(gateway.calls, ['start', 'items:1']);
  });

  test('성공한 청크 응답의 매핑이 잘못되면 클라이언트가 세션을 취소한다', () async {
    final gateway = _FakeGateway(mismatchedUploadResponse: true);

    await expectLater(
      () => ExternalRecordImportService(api: gateway).run(input()),
      throwsA(
        isA<ExternalImportException>().having(
          (error) => error.reason,
          'reason',
          'record_import_mapping_mismatch',
        ),
      ),
    );
    expect(gateway.calls, ['start', 'items:1', 'cancel:1']);
  });

  test('서버가 전달한 가져오기 실패 사유를 사용자에게 보존한다', () async {
    final gateway = _FakeGateway(
      uploadError: const RecordImportException(
        '가져올 수 없는 북모리 기록이 있어요.',
        kind: RecordImportFailureKind.requestFailed,
        statusCode: 400,
        serverMessage: '가져올 수 없는 북모리 기록이 있어요.',
      ),
    );

    await expectLater(
      () => ExternalRecordImportService(api: gateway).run(input()),
      throwsA(
        isA<ExternalImportException>().having(
          (error) => error.userMessage,
          'userMessage',
          '가져올 수 없는 북모리 기록이 있어요.',
        ),
      ),
    );
  });

  test('활성 충돌이 없는데 서버가 재사용한 ISBN 책은 삭제 행 복구로 구분한다', () async {
    final gateway = _FakeGateway(bookCreated: false);
    final result = await ExternalRecordImportService(api: gateway).run(
      const ExternalImportParseResult(
        source: ExternalImportSource.bookmory,
        discoveredBookCount: 1,
        skippedItemCount: 0,
        warningCount: 0,
        books: [
          ExternalBookImportItem(
            source: ExternalImportSource.bookmory,
            sourceBookId: 'book-1',
            isbn13: '9781234567890',
            title: '책',
            status: BookStatus.finished,
            currentPage: 0,
            rereadCount: 0,
            notes: [
              ExternalNoteImportItem(
                type: ExternalNoteType.thought,
                content: '가져온 메모',
              ),
            ],
            tags: [],
          ),
        ],
      ),
    );

    expect(result.restoredBooksByIsbn.keys, {'9781234567890'});
    final restored = result.restoredBooksByIsbn['9781234567890']!;
    expect(restored.bookServerId, 1000);
    expect(restored.importedNoteServerIds, {2000});
    expect(restored.importedNoteMemoServerIds, {3000});
  });

  test('응답 개수가 같아도 localId가 요청과 다르면 세션을 취소한다', () async {
    final gateway = _FakeGateway(wrongLocalIdResponse: true);

    await expectLater(
      () => ExternalRecordImportService(api: gateway).run(input()),
      throwsA(
        isA<ExternalImportException>().having(
          (error) => error.reason,
          'reason',
          'record_import_mapping_mismatch',
        ),
      ),
    );
    expect(gateway.calls, ['start', 'items:1', 'cancel:1']);
  });

  test('복구 책 정리는 이번 Import에 없는 서버 노트와 메모만 대상으로 삼는다', () {
    final now = DateTime.utc(2026, 9, 11);
    BookNote note(int id, int? serverId) => BookNote(
      id: id,
      serverId: serverId,
      userBookId: 1,
      title: null,
      deletedAt: null,
      createdAt: now,
      updatedAt: now,
      isDirty: false,
    );
    BookNoteMemo memo(int id, int? serverId) => BookNoteMemo(
      id: id,
      serverId: serverId,
      clientRequestId: null,
      noteId: 10,
      type: BookNoteMemoType.thought,
      startPage: null,
      endPage: null,
      content: '메모',
      imageUrl: null,
      localImagePath: id == 102 ? 'memo_images/stale.jpg' : null,
      isImportant: false,
      sortOrder: 0,
      deletedAt: null,
      createdAt: now,
      updatedAt: now,
      isDirty: false,
    );
    final importedNote = note(10, 200);
    final staleNote = note(11, 201);
    final localOnlyNote = note(12, null);
    final plan = buildRestoredBookMemoCleanupPlan(
      imported: const RestoredBookImportArtifacts(
        bookServerId: 100,
        importedNoteServerIds: {200},
        importedNoteMemoServerIds: {300},
      ),
      summaries: [
        BookNoteSummary(
          note: importedNote,
          memoCount: 3,
          firstPage: null,
          lastPage: null,
        ),
        BookNoteSummary(
          note: staleNote,
          memoCount: 1,
          firstPage: null,
          lastPage: null,
        ),
        BookNoteSummary(
          note: localOnlyNote,
          memoCount: 1,
          firstPage: null,
          lastPage: null,
        ),
      ],
      detailsByNoteLocalId: {
        importedNote.id: BookNoteDetail(
          note: importedNote,
          memos: [memo(100, 300), memo(102, 301), memo(103, null)],
        ),
      },
    );

    expect(plan, isNotNull);
    final confirmedPlan = plan!;
    expect(confirmedPlan.noteLocalIds, [staleNote.id]);
    expect(confirmedPlan.memoTargets, hasLength(1));
    expect(confirmedPlan.memoTargets.single.noteLocalId, importedNote.id);
    expect(confirmedPlan.memoTargets.single.memoLocalId, 102);
    expect(
      confirmedPlan.memoTargets.single.previousLocalImagePath,
      'memo_images/stale.jpg',
    );
  });

  test('Import 응답 ID를 동기화 결과에서 확인하지 못하면 복구 메모를 정리하지 않는다', () {
    final plan = buildRestoredBookMemoCleanupPlan(
      imported: const RestoredBookImportArtifacts(
        bookServerId: 100,
        importedNoteServerIds: {200},
        importedNoteMemoServerIds: {300},
      ),
      summaries: const [],
      detailsByNoteLocalId: const {},
    );

    expect(plan, isNull);
  });

  test('실행 잠금은 한 가져오기만 허용하고 소유자만 해제할 수 있다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final lock = container.read(externalImportExecutionLockProvider.notifier);
    final first = Object();
    final second = Object();

    expect(lock.tryAcquire(userId: 10, owner: first), isTrue);
    expect(container.read(externalImportExecutionLockProvider), 10);
    expect(lock.tryAcquire(userId: 10, owner: second), isFalse);

    lock.release(second);
    expect(container.read(externalImportExecutionLockProvider), 10);
    lock.release(first);
    expect(container.read(externalImportExecutionLockProvider), isNull);
    expect(lock.tryAcquire(userId: 10, owner: second), isTrue);
  });
}

class _FakeGateway implements ExternalRecordImportGateway {
  _FakeGateway({
    this.firstImportedCount = 0,
    this.failUpload = false,
    this.uploadError,
    this.bookCreated = true,
    this.mismatchedUploadResponse = false,
    this.wrongLocalIdResponse = false,
  });

  final int firstImportedCount;
  final bool failUpload;
  final RecordImportException? uploadError;
  final bool bookCreated;
  final bool mismatchedUploadResponse;
  final bool wrongLocalIdResponse;
  final List<String> calls = [];
  RecordImportCounts? completedCounts;
  var starts = 0;

  @override
  Future<RecordImportSession> start() async {
    starts++;
    calls.add('start');
    return RecordImportSession(
      importId: starts,
      status: 'IN_PROGRESS',
      importedCount: starts == 1 ? firstImportedCount : 0,
      maxChunkItemCount: 500,
      createdAt: DateTime.utc(2026, 9, 10),
    );
  }

  @override
  Future<RecordImportChunkResult> uploadItems(
    int importId,
    Map<String, dynamic> payload,
  ) async {
    calls.add('items:$importId');
    if (uploadError case final error?) throw error;
    if (failUpload) {
      throw const RecordImportException(
        'failed',
        kind: RecordImportFailureKind.requestFailed,
      );
    }
    List<RecordImportEntityResult> mappings(
      String key,
      int serverIdBase, {
      bool created = true,
    }) {
      final items = payload[key] as List<dynamic>;
      return [
        for (var index = 0; index < items.length; index++)
          RecordImportEntityResult(
            localId: (items[index] as Map<String, dynamic>)['localId'] as int,
            serverId: serverIdBase + index,
            created: created,
          ),
      ];
    }

    final books = mappings('books', 1000, created: bookCreated);
    final notes = mappings('notes', 2000);
    final noteMemos = mappings('noteMemos', 3000);
    final reflections = mappings('reflections', 4000);
    final tags = mappings('tags', 5000);
    final tagMaps = mappings('tagMaps', 6000);
    if (mismatchedUploadResponse) {
      return RecordImportChunkResult(
        books: const [],
        notes: notes,
        noteMemos: noteMemos,
        reflections: reflections,
        tags: tags,
        tagMaps: tagMaps,
        importedCount: 0,
      );
    }
    if (wrongLocalIdResponse) {
      return RecordImportChunkResult(
        books: [
          for (final book in books)
            RecordImportEntityResult(
              localId: book.localId - 1000,
              serverId: book.serverId,
              created: book.created,
            ),
        ],
        notes: notes,
        noteMemos: noteMemos,
        reflections: reflections,
        tags: tags,
        tagMaps: tagMaps,
        importedCount: 0,
      );
    }
    return RecordImportChunkResult(
      books: books,
      notes: notes,
      noteMemos: noteMemos,
      reflections: reflections,
      tags: tags,
      tagMaps: tagMaps,
      importedCount:
          books.length +
          notes.length +
          noteMemos.length +
          reflections.length +
          tags.length +
          tagMaps.length,
    );
  }

  @override
  Future<void> complete(int importId, RecordImportCounts counts) async {
    calls.add('complete:$importId');
    completedCounts = counts;
  }

  @override
  Future<void> cancel(int importId) async {
    calls.add('cancel:$importId');
  }
}
