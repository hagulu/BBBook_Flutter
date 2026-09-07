import 'dart:io';

import 'package:bbbook/features/book_note/models/book_note.dart';
import 'package:bbbook/features/book_reflection/models/book_reflection.dart';
import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/server_storage_migration/data/record_import_payload_builder.dart';
import 'package:bbbook/features/server_storage_migration/data/record_import_snapshot.dart';
import 'package:bbbook/features/server_storage_migration/data/server_storage_migration_steps.dart';
import 'package:bbbook/features/server_storage_migration/models/record_import_models.dart';
import 'package:bbbook/features/server_storage_migration/services/server_storage_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 로컬 → 서버 저장 재전환의 순서와 중단 조건 테스트.
///
/// 이 서비스는 청크 응답을 받는 즉시가 아니라 `/complete` 성공 뒤에만
/// 로컬 DB에 서버 ID를 반영해야 한다 — 순서가 바뀌면, 이후 단계가 실패해
/// 서버가 세션 전체를 정리했을 때 로컬에는 더 이상 존재하지 않는 서버
/// 행의 ID가 남아 다음 전체 동기화가 로컬 원본까지 지워버릴 수 있다.
void main() {
  final emptySnapshot = const RecordImportSnapshot(
    books: [],
    tags: [],
    notes: [],
    noteMemos: [],
    reflections: [],
    tagMaps: [],
    pendingMemoImages: {},
    pendingReflectionImages: {},
  );

  test('빈 스냅샷도 처음부터 끝까지 정상 완료된다', () async {
    final steps = _FakeSteps(
      outcome: RecordImportPreflightOutcome.success(emptySnapshot),
    );

    final result = await ServerStorageMigrationService(steps).run();

    expect(result.stage, ServerStorageMigrationStage.completed);
    expect(steps.calls, [
      'ensureNoPendingServerCleanup',
      'prepare',
      'startSession',
      // 보낼 항목이 없으니 uploadChunk는 없어야 한다.
      'complete',
      'applyResults',
      'switchToServerMode',
    ]);
  });

  test('사전 검증 실패면 세션을 시작하지도 않는다', () async {
    final steps = _FakeSteps(
      outcome: RecordImportPreflightOutcome.failure('이미지를 찾을 수 없습니다.'),
    );

    final result = await ServerStorageMigrationService(steps).run();

    expect(result.stage, ServerStorageMigrationStage.failed);
    expect(result.failureMessage, '이미지를 찾을 수 없습니다.');
    expect(steps.calls, ['ensureNoPendingServerCleanup', 'prepare']);
  });

  test('서버 기록 정리 미완료 상태를 풀지 못하면 준비 단계로 넘어가지 않는다', () async {
    final steps = _FakeSteps(
      outcome: RecordImportPreflightOutcome.success(emptySnapshot),
      cleanupOk: false,
    );

    final result = await ServerStorageMigrationService(steps).run();

    expect(result.stage, ServerStorageMigrationStage.failed);
    expect(steps.calls, ['ensureNoPendingServerCleanup']);
  });

  test('청크 업로드가 실패하면 complete·applyResults를 호출하지 않는다', () async {
    // 문서상 items 실패는 서버가 세션 전체를 이미 정리하므로, 여기서 별도
    // 취소를 호출할 필요가 없다(그래서 이 인터페이스에는 cancel이 없다).
    final book = _bookItem(userBookId: -1);
    final snapshot = RecordImportSnapshot(
      books: [book],
      tags: const [],
      notes: const [],
      noteMemos: const [],
      reflections: const [],
      tagMaps: const [],
      pendingMemoImages: const {},
      pendingReflectionImages: const {},
    );
    final steps = _FakeSteps(
      outcome: RecordImportPreflightOutcome.success(snapshot),
      failOn: 'uploadChunk',
    );

    final result = await ServerStorageMigrationService(steps).run();

    expect(result.stage, ServerStorageMigrationStage.failed);
    expect(steps.calls, contains('uploadChunk'));
    expect(steps.calls, isNot(contains('complete')));
    expect(steps.calls, isNot(contains('applyResults')));
    expect(steps.calls, isNot(contains('switchToServerMode')));
  });

  test('청크 응답의 서버 ID는 complete가 성공한 뒤에만 로컬에 반영된다', () async {
    final book = _bookItem(userBookId: -1);
    final snapshot = RecordImportSnapshot(
      books: [book],
      tags: const [],
      notes: const [],
      noteMemos: const [],
      reflections: const [],
      tagMaps: const [],
      pendingMemoImages: const {},
      pendingReflectionImages: const {},
    );
    final steps = _FakeSteps(
      outcome: RecordImportPreflightOutcome.success(snapshot),
    );

    final result = await ServerStorageMigrationService(steps).run();

    expect(result.stage, ServerStorageMigrationStage.completed);
    expect(steps.calls.indexOf('uploadChunk'), lessThan(steps.calls.indexOf('complete')));
    expect(steps.calls.indexOf('complete'), lessThan(steps.calls.indexOf('applyResults')));
    expect(steps.appliedResults!.bookServerIdByLocalId[-1], isNotNull);
  });

  test('PHOTO 메모 사진과 독후감 이미지를 기록 업로드 이후에만 올린다', () async {
    final book = _bookItem(userBookId: -1);
    final note = BookNote(
      id: -1,
      serverId: null,
      userBookId: -1,
      title: '노트',
      deletedAt: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      isDirty: true,
    );
    final memo = BookNoteMemo(
      id: -1,
      serverId: null,
      clientRequestId: 'memo-crid',
      noteId: -1,
      type: BookNoteMemoType.photo,
      startPage: null,
      endPage: null,
      content: null,
      imageUrl: null,
      localImagePath: 'memo_images/a.jpg',
      isImportant: false,
      sortOrder: 0,
      deletedAt: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      isDirty: true,
    );
    final reflection = BookReflection(
      id: -1,
      serverId: null,
      clientRequestId: 'reflection-crid',
      userBookId: -1,
      reflectionType: 'USER_WRITTEN',
      title: '독후감',
      contentJson: const {
        'ops': [
          {
            'insert': {'image': 'local://reflection/-1/0'},
          },
        ],
      },
      contentText: '본문',
      isPublic: false,
      isHidden: false,
      deletedAt: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      isDirty: true,
    );
    final snapshot = RecordImportSnapshot(
      books: [book],
      tags: const [],
      notes: [note],
      noteMemos: [memo],
      reflections: [
        ReflectionForImport(
          reflection: reflection,
          contentJsonForImport: reflection.contentJson!,
        ),
      ],
      tagMaps: const [],
      pendingMemoImages: {-1: File('memo.jpg')},
      pendingReflectionImages: {
        -1: [
          ReflectionImagePlaceholder(
            placeholder: 'local://reflection/-1/0',
            file: File('reflection.jpg'),
            localImagePath: 'reflection_images/x.jpg',
          ),
        ],
      },
    );
    final steps = _FakeSteps(
      outcome: RecordImportPreflightOutcome.success(snapshot),
    );

    final result = await ServerStorageMigrationService(steps).run();

    expect(result.stage, ServerStorageMigrationStage.completed);
    final uploadChunkIndex = steps.calls.indexOf('uploadChunk');
    final memoIndex = steps.calls.indexOf('uploadMemoImage');
    final reflectionIndex = steps.calls.indexOf('uploadReflectionImage');
    final completeIndex = steps.calls.indexOf('complete');
    expect(uploadChunkIndex, lessThan(memoIndex));
    expect(uploadChunkIndex, lessThan(reflectionIndex));
    expect(memoIndex, lessThan(completeIndex));
    expect(reflectionIndex, lessThan(completeIndex));
    expect(
      steps.appliedResults!.memoImageUrlByLocalId[-1],
      isNotNull,
    );
    expect(
      steps.appliedResults!.reflectionResultsByLocalId[-1]!.uploadedImages,
      isNotEmpty,
    );
  });

  test(
    '이미 imageUrl이 있던 PHOTO 메모가 실제로는 새로 생성되면 예비 파일을 올린다',
    () async {
      // 로컬 imageUrl이 있어 보통은 첨부를 건너뛰지만, 청크 응답이
      // created:true(서버가 옛 행을 이미 물리 정리해 완전히 새로 만든
      // 경우)를 돌려주면 그 새 행에는 사진이 전혀 없으므로 예비로 들고
      // 있던 로컬 파일을 올려야 한다.
      final book = _bookItem(userBookId: -1);
      final note = BookNote(
        id: -1,
        serverId: null,
        userBookId: -1,
        title: '노트',
        deletedAt: null,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        isDirty: true,
      );
      final memo = BookNoteMemo(
        id: -1,
        serverId: null,
        clientRequestId: 'memo-crid',
        noteId: -1,
        type: BookNoteMemoType.photo,
        startPage: null,
        endPage: null,
        content: null,
        imageUrl: 'https://old.example.com/notes/1/a.jpg',
        localImagePath: 'memo_images/a.jpg',
        isImportant: false,
        sortOrder: 0,
        deletedAt: null,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        isDirty: true,
      );
      final snapshot = RecordImportSnapshot(
        books: [book],
        tags: const [],
        notes: [note],
        noteMemos: [memo],
        reflections: const [],
        tagMaps: const [],
        pendingMemoImages: const {},
        fallbackMemoImages: {-1: File('memo.jpg')},
        pendingReflectionImages: const {},
      );
      final steps = _FakeSteps(
        outcome: RecordImportPreflightOutcome.success(snapshot),
      );

      final result = await ServerStorageMigrationService(steps).run();

      expect(result.stage, ServerStorageMigrationStage.completed);
      expect(steps.memoImageUploads, [-1]);
    },
  );

  test('이미 imageUrl이 있던 PHOTO 메모가 그대로 복원되면 다시 올리지 않는다', () async {
    final book = _bookItem(userBookId: -1);
    final note = BookNote(
      id: -1,
      serverId: null,
      userBookId: -1,
      title: '노트',
      deletedAt: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      isDirty: true,
    );
    final memo = BookNoteMemo(
      id: -1,
      serverId: null,
      clientRequestId: 'memo-crid',
      noteId: -1,
      type: BookNoteMemoType.photo,
      startPage: null,
      endPage: null,
      content: null,
      imageUrl: 'https://old.example.com/notes/1/a.jpg',
      localImagePath: 'memo_images/a.jpg',
      isImportant: false,
      sortOrder: 0,
      deletedAt: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      isDirty: true,
    );
    final snapshot = RecordImportSnapshot(
      books: [book],
      tags: const [],
      notes: [note],
      noteMemos: [memo],
      reflections: const [],
      tagMaps: const [],
      pendingMemoImages: const {},
      fallbackMemoImages: {-1: File('memo.jpg')},
      pendingReflectionImages: const {},
    );
    final steps = _FakeSteps(
      outcome: RecordImportPreflightOutcome.success(snapshot),
      notCreatedMemoLocalIds: {-1},
    );

    final result = await ServerStorageMigrationService(steps).run();

    expect(result.stage, ServerStorageMigrationStage.completed);
    expect(steps.memoImageUploads, isEmpty);
  });

  test('세션이 내려준 maxChunkItemCount 단위로 나눠 여러 번 업로드한다', () async {
    final books = List.generate(3, (i) => _bookItem(userBookId: -(i + 1)));
    final snapshot = RecordImportSnapshot(
      books: books,
      tags: const [],
      notes: const [],
      noteMemos: const [],
      reflections: const [],
      tagMaps: const [],
      pendingMemoImages: const {},
      pendingReflectionImages: const {},
    );
    final steps = _FakeSteps(
      outcome: RecordImportPreflightOutcome.success(snapshot),
      maxChunkItemCount: 1,
    );

    final result = await ServerStorageMigrationService(steps).run();

    expect(result.stage, ServerStorageMigrationStage.completed);
    expect(steps.calls.where((c) => c == 'uploadChunk').length, 3);
    expect(steps.appliedResults!.bookServerIdByLocalId.length, 3);
  });

  test('진행 단계를 순서대로 알린다', () async {
    final book = _bookItem(userBookId: -1);
    final snapshot = RecordImportSnapshot(
      books: [book],
      tags: const [],
      notes: const [],
      noteMemos: const [],
      reflections: const [],
      tagMaps: const [],
      pendingMemoImages: const {},
      pendingReflectionImages: const {},
    );
    final steps = _FakeSteps(
      outcome: RecordImportPreflightOutcome.success(snapshot),
    );
    final stages = <ServerStorageMigrationStage>[];

    await ServerStorageMigrationService(steps).run(
      onProgress: (state) {
        if (stages.isEmpty || stages.last != state.stage) {
          stages.add(state.stage);
        }
      },
    );

    expect(stages, [
      ServerStorageMigrationStage.preparing,
      ServerStorageMigrationStage.uploadingRecords,
      ServerStorageMigrationStage.uploadingImages,
      ServerStorageMigrationStage.completing,
      ServerStorageMigrationStage.completed,
    ]);
  });
}

BookItem _bookItem({required int userBookId}) {
  return BookItem(
    userBookId: userBookId,
    serverId: null,
    clientRequestId: 'book-crid',
    title: '책 제목',
    status: BookStatus.reading,
    currentPage: 10,
    isMasterpiece: false,
    rereadCount: 0,
    tags: const [],
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
  );
}

class _FakeSteps implements ServerStorageMigrationSteps {
  _FakeSteps({
    required this.outcome,
    this.maxChunkItemCount = 500,
    this.failOn,
    this.cleanupOk = true,
    this.notCreatedMemoLocalIds = const {},
  });

  final RecordImportPreflightOutcome outcome;
  final int maxChunkItemCount;
  final String? failOn;
  final bool cleanupOk;

  /// 이 목록에 있는 noteMemo localId는 청크 응답에서 `created: false`로
  /// 돌려준다(기본은 모두 `created: true`).
  final Set<int> notCreatedMemoLocalIds;

  final calls = <String>[];
  final memoImageUploads = <int>[];
  RecordImportAppliedResults? appliedResults;
  var _nextServerId = 100;

  void _record(String name) {
    calls.add(name);
    if (failOn == name) throw StateError('$name failed');
  }

  @override
  Future<bool> ensureNoPendingServerCleanup() async {
    _record('ensureNoPendingServerCleanup');
    return cleanupOk;
  }

  @override
  Future<RecordImportPreflightOutcome> prepare() async {
    _record('prepare');
    return outcome;
  }

  @override
  Future<RecordImportSession> startSession() async {
    _record('startSession');
    return RecordImportSession(
      importId: 1,
      status: 'IN_PROGRESS',
      importedCount: 0,
      maxChunkItemCount: maxChunkItemCount,
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<RecordImportChunkResult> uploadChunk(
    int importId,
    RecordImportChunk chunk,
  ) async {
    _record('uploadChunk');
    RecordImportEntityResult map(Map<String, dynamic> item) {
      return RecordImportEntityResult(
        localId: item['localId'] as int,
        serverId: _nextServerId++,
        created: true,
      );
    }

    RecordImportEntityResult mapMemo(Map<String, dynamic> item) {
      final localId = item['localId'] as int;
      return RecordImportEntityResult(
        localId: localId,
        serverId: _nextServerId++,
        created: !notCreatedMemoLocalIds.contains(localId),
      );
    }

    return RecordImportChunkResult(
      books: chunk.books.map(map).toList(),
      notes: chunk.notes.map(map).toList(),
      noteMemos: chunk.noteMemos.map(mapMemo).toList(),
      reflections: chunk.reflections.map(map).toList(),
      tags: chunk.tags.map(map).toList(),
      tagMaps: chunk.tagMaps.map(map).toList(),
      importedCount: 0,
    );
  }

  @override
  Future<RecordImportAttachmentResult> uploadMemoImage(
    int importId,
    int memoLocalId,
    File file,
  ) async {
    _record('uploadMemoImage');
    memoImageUploads.add(memoLocalId);
    return RecordImportAttachmentResult(
      localId: memoLocalId,
      serverId: 1,
      imageUrl: 'notes/1/imports/1/a.jpg',
    );
  }

  @override
  Future<RecordImportAttachmentResult> uploadReflectionImage(
    int importId,
    int reflectionLocalId,
    String placeholder,
    File file,
  ) async {
    _record('uploadReflectionImage');
    return RecordImportAttachmentResult(
      localId: reflectionLocalId,
      serverId: 1,
      imageUrl: 'https://cdn.example.com/reflections/1/imports/1/b.jpg',
    );
  }

  @override
  Future<void> complete(int importId, RecordImportCounts counts) async =>
      _record('complete');

  @override
  Future<void> applyResults(RecordImportAppliedResults results) async {
    appliedResults = results;
    _record('applyResults');
  }

  @override
  Future<void> switchToServerMode() async => _record('switchToServerMode');
}
