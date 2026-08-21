import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_exception.dart';
import '../../bookshelf/data/bookshelf_repository.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../record_sync/data/record_sync_api.dart';
import '../../record_sync/models/record_sync_payload.dart';
import '../models/book_note.dart';
import '../utils/memo_highlight.dart';
import 'book_note_api.dart';
import 'book_note_dao.dart';

/// 노트 화면의 source of truth.
///
/// 화면은 항상 이 Repository를 통해 로컬 DB만 읽고 쓴다. 저장/수정/삭제는
/// 로컬에 즉시 반영하고 `is_dirty=1`로 표시한 뒤([BookNoteDao]), 그 자리에서
/// 조용히 서버로 push를 시도한다([pushNote]) — 성공하면 dirty가 풀리고,
/// 실패(오프라인 등)하면 dirty가 남아 다음 [sync] 호출 때 재시도된다. 즉
/// 화면의 CRUD 호출은 네트워크 실패와 무관하게 항상 즉시 완료된다.
///
/// [sync]는 dirty push를 먼저 처리한 뒤, 로컬에 동기화 기준값(마지막 since)이
/// 없으면(최초 로그인 등) 전체 동기화를, 있으면 증분 동기화를 수행한다.
class BookNoteRepository {
  BookNoteRepository({
    required this._api,
    required this._recordSyncApi,
    required this._bookshelfRepository,
    this._dao = const BookNoteDao(),
  });

  final BookNoteApi _api;
  final RecordSyncApi _recordSyncApi;
  final BookshelfRepository _bookshelfRepository;
  final BookNoteDao _dao;

  /// [pushNote] 호출을 노트별로 순서대로 실행시키는 체인.
  /// [BookshelfRepository._dirtyPushChains]와 같은 이유로 필요하다: 서버에
  /// 아직 없는(로컬 음수 ID) 노트에 대해 겹치는 push가 동시에 나가면 제목
  /// PUT(또는 첫 메모 POST)이 두 번 실행되어 서버에 노트가 두 개 생길 수
  /// 있다.
  final Map<int, Future<void>> _dirtyPushChains = {};

  Future<List<BookNoteSummary>> findByUserBook({
    required int ownerUserId,
    required int userBookId,
  }) {
    return _dao.findByUserBook(
      ownerUserId: ownerUserId,
      userBookId: userBookId,
    );
  }

  Future<BookNoteDetail?> findDetail({
    required int ownerUserId,
    required int userBookId,
    required int noteId,
  }) {
    return _dao.findDetail(
      ownerUserId: ownerUserId,
      userBookId: userBookId,
      noteId: noteId,
    );
  }

  Future<BookNote> saveTitle({
    required int ownerUserId,
    required int userBookId,
    required int? noteId,
    required String? title,
  }) async {
    final operation = noteId == null ? '노트 생성' : '노트 제목 수정';
    try {
      final note = noteId == null
          ? await _dao.createNote(
              ownerUserId: ownerUserId,
              userBookId: userBookId,
              title: title,
            )
          : await _dao.updateTitle(
              ownerUserId: ownerUserId,
              userBookId: userBookId,
              noteId: noteId,
              title: title,
            );
      developer.log(
        '[$operation] userId=$ownerUserId bookId=$userBookId '
        'noteId=${note.id} result=SUCCESS',
      );
      unawaited(pushNote(note.id));
      return note;
    } catch (error) {
      developer.log(
        '[$operation] userId=$ownerUserId bookId=$userBookId '
        'noteId=${noteId ?? 'new'} result=FAIL reason=local_storage_error',
      );
      rethrow;
    }
  }

  Future<BookNoteMemo> createNoteMemo({
    required int ownerUserId,
    required int userBookId,
    required int noteId,
    required BookNoteMemoDraft draft,
  }) async {
    draft = _normalizeDraftImportance(draft);
    String? imageUrl;
    try {
      imageUrl = await _resolveImageUrl(draft);
      final memo = await _dao.createNoteMemo(
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        noteId: noteId,
        draft: draft,
        imageUrl: imageUrl,
      );
      developer.log(
        '[메모 생성] userId=$ownerUserId bookId=$userBookId '
        'noteId=$noteId noteMemoId=${memo.id} result=SUCCESS',
      );
      unawaited(pushNote(noteId));
      return memo;
    } catch (error) {
      if (draft.pickedImagePath != null) {
        await _deleteManagedImage(imageUrl);
      }
      developer.log(
        '[메모 생성] userId=$ownerUserId bookId=$userBookId '
        'noteId=$noteId result=FAIL reason=local_storage_error',
      );
      rethrow;
    }
  }

  Future<BookNoteMemo> updateNoteMemo({
    required int ownerUserId,
    required int userBookId,
    required int noteId,
    required int noteMemoId,
    required BookNoteMemoDraft draft,
    required String? previousImageUrl,
  }) async {
    draft = _normalizeDraftImportance(draft);
    String? imageUrl;
    try {
      imageUrl = await _resolveImageUrl(draft);
      final memo = await _dao.updateNoteMemo(
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        noteId: noteId,
        noteMemoId: noteMemoId,
        draft: draft,
        imageUrl: imageUrl,
      );
      await _deleteManagedImage(previousImageUrl, except: imageUrl);
      developer.log(
        '[메모 수정] userId=$ownerUserId bookId=$userBookId '
        'noteId=$noteId noteMemoId=$noteMemoId result=SUCCESS',
      );
      unawaited(pushNote(noteId));
      return memo;
    } catch (error) {
      if (draft.pickedImagePath != null) {
        await _deleteManagedImage(imageUrl);
      }
      developer.log(
        '[메모 수정] userId=$ownerUserId bookId=$userBookId '
        'noteId=$noteId noteMemoId=$noteMemoId result=FAIL '
        'reason=local_storage_error',
      );
      rethrow;
    }
  }

  /// 텍스트 메모의 `isImportant`는 별도 입력이 아니라 [BookNoteMemoDraft.content]
  /// 안의 `::hl[[]]` 강조 존재 여부로만 정해진다. 에디터가 이미 계산해 보내더라도
  /// 이 한 곳에서 다시 파생시켜, 어느 화면(퀵 작성 등)에서 만든 draft든 규칙이
  /// 어긋나지 않게 한다. PHOTO는 메모 전체 강조가 수동 입력값이라 그대로 둔다.
  /// 서버 동기화/reconcile 경로는 이미 같은 규칙으로 계산된 서버 값을 신뢰하므로
  /// 여기서 건드리지 않는다.
  BookNoteMemoDraft _normalizeDraftImportance(BookNoteMemoDraft draft) {
    if (draft.type == BookNoteMemoType.photo) return draft;
    final derived = hasMemoHighlight(draft.content);
    if (derived == draft.isImportant) return draft;
    return BookNoteMemoDraft(
      type: draft.type,
      startPage: draft.startPage,
      endPage: draft.endPage,
      content: draft.content,
      imageUrl: draft.imageUrl,
      pickedImagePath: draft.pickedImagePath,
      isImportant: derived,
    );
  }

  Future<DeleteNoteMemoResult> deleteNoteMemo({
    required int ownerUserId,
    required int userBookId,
    required int noteId,
    required int noteMemoId,
    required String? previousImageUrl,
  }) async {
    try {
      final result = await _dao.deleteNoteMemo(
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        noteId: noteId,
        noteMemoId: noteMemoId,
      );
      await _deleteManagedImage(previousImageUrl);
      developer.log(
        '[메모 삭제] userId=$ownerUserId bookId=$userBookId '
        'noteId=$noteId noteMemoId=$noteMemoId result=SUCCESS',
      );
      unawaited(pushNote(noteId));
      return result;
    } catch (error) {
      developer.log(
        '[메모 삭제] userId=$ownerUserId bookId=$userBookId '
        'noteId=$noteId noteMemoId=$noteMemoId result=FAIL '
        'reason=local_storage_error',
      );
      rethrow;
    }
  }

  Future<void> deleteNote({
    required int ownerUserId,
    required int userBookId,
    required int noteId,
  }) async {
    try {
      await _dao.deleteNote(
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        noteId: noteId,
      );
      developer.log(
        '[노트 삭제] userId=$ownerUserId bookId=$userBookId '
        'noteId=$noteId result=SUCCESS',
      );
      unawaited(pushNote(noteId));
    } catch (error) {
      developer.log(
        '[노트 삭제] userId=$ownerUserId bookId=$userBookId '
        'noteId=$noteId result=FAIL reason=local_storage_error',
      );
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // 서버 동기화
  // ---------------------------------------------------------------------

  Future<DateTime?> getLastSyncedAtNote() => _dao.getLastSyncedAtNote();

  /// dirty push(제목/메모 생성·수정·삭제) → since가 없으면 전체 동기화,
  /// 있으면 증분 동기화 → 증분 응답이 fullSyncRequired면 전체 동기화로 대체.
  /// [BookshelfRepository.sync]와 같은 구조다.
  ///
  /// 반환값은 실제로 로컬 DB가 바뀌었는지 여부.
  Future<bool> sync({required int ownerUserId}) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;

    await pushAllDirty();
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }

    final since = await _dao.getLastSyncedAtNote();
    if (since == null) {
      return _fullSync(ownerUserId, expectedGeneration);
    }

    final result = await _api.getSyncChanges(since: since);
    if (result.fullSyncRequired) {
      // 증분 응답의 syncedAt(서버 시각)을 기준값으로 쓴다 — 클라이언트
      // now()를 쓰면 기기 시계가 서버보다 앞서 있을 때 그 오차만큼 이후
      // 서버 변경을 영구히 놓칠 수 있다.
      return _fullSync(
        ownerUserId,
        expectedGeneration,
        baseline: result.syncedAt,
      );
    }
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }

    await _dao.applyNoteChanges(
      ownerUserId: ownerUserId,
      upsertedNotes: result.upsertedNotes,
      deletedNoteIds: result.deletedNoteIds,
      upsertedNoteMemos: result.upsertedNoteMemos,
      deletedNoteMemoIds: result.deletedNoteMemoIds,
      syncedAt: result.syncedAt,
    );
    return result.upsertedNotes.isNotEmpty ||
        result.deletedNoteIds.isNotEmpty ||
        result.upsertedNoteMemos.isNotEmpty ||
        result.deletedNoteMemoIds.isNotEmpty;
  }

  /// [baseline]을 넘기지 않으면(최초 동기화 등 서버 시각을 알 수 없을 때)
  /// 요청 직전 클라이언트 시각(UTC)을 기준값으로 쓴다. `/api/me/records`(최초
  /// 기록 전체 조회 — record_sync 기능과 같은 API)를 그대로 재사용한다.
  /// api-doc(`api-me-notes-sync-changes-get.md`)이 `fullSyncRequired`일 때의
  /// 복구 경로로 이 API를 명시하고 있다.
  Future<bool> _fullSync(
    int ownerUserId,
    int expectedGeneration, {
    DateTime? baseline,
  }) async {
    final requestedAt = baseline ?? DateTime.now().toUtc();
    final payload = await _recordSyncApi.getAllRecords();
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }
    await _dao.reconcileFullNotes(
      ownerUserId: ownerUserId,
      activeUserBookIds: payload.books
          .map((b) => b.userBookId)
          .toList(growable: false),
      notes: payload.notes,
      noteMemos: payload.noteMemos,
      requestedAt: requestedAt,
    );
    return true;
  }

  /// dirty 표시된 노트/메모를 모두 서버로 일괄 재전송한다. 각 노트는
  /// 독립적으로 처리한다 — 하나가 실패해도 다른 노트의 push는 계속
  /// 시도하고, dirty가 남은 노트는 다음 [sync] 때 다시 재시도된다.
  Future<void> pushAllDirty() async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final noteIds = <int>{
      ...await _dao.getDirtyNoteLocalIds(),
      ...await _dao.getNoteIdsWithDirtyMemos(),
    };
    for (final id in noteIds) {
      if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
      await pushNote(id);
    }
  }

  /// 특정 노트(제목 + 메모 전체)의 dirty 로컬 편집을 서버로 push한다. 편집
  /// 직후([saveTitle]/[createNoteMemo]/[updateNoteMemo]/[deleteNoteMemo])와
  /// 동기화 시점([pushAllDirty]) 모두에서 호출되며, 같은 노트에 대한 동시
  /// 호출은 [_dirtyPushChains]로 직렬화한다.
  Future<void> pushNote(int localNoteId) {
    final previous = _dirtyPushChains[localNoteId] ?? Future<void>.value();
    final chained = previous
        .then((_) => _pushOneNote(localNoteId))
        // 체인에 쌓인 Future가 에러로 완료되면 뒤에 이어붙는 호출들이 전부
        // 건너뛰어지므로 여기서 삼켜 체인이 끊기지 않게 한다(실패는 이미
        // 내부에서 로그로만 남기고 dirty를 유지한다).
        .catchError((_, _) {});
    _dirtyPushChains[localNoteId] = chained;
    return chained;
  }

  Future<void> _pushOneNote(int localNoteId) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final note = await _dao.getNoteByLocalId(localNoteId);
    if (note == null) return; // 이미 로컬에서 정리됨
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
    final serverUserBookId = await _resolveServerUserBookId(note.userBookId);
    if (serverUserBookId == null) {
      developer.log(
        '[노트 더티 push] localUserBookId=${note.userBookId} '
        'result=FAIL reason=book_create_pending',
      );
      return;
    }

    // 소프트 삭제된 노트는 제목/메모 push를 전혀 거치지 않고 노트 전용
    // 삭제 API 한 번으로 끝낸다 — 메모까지 서버가 함께 지워준다.
    if (note.deletedAt != null) {
      await _pushDeletedNote(serverUserBookId, note, expectedGeneration);
      return;
    }

    int? serverNoteId = note.serverId;
    if (serverNoteId == null) {
      if (note.title != null) {
        try {
          final result = await _api.putTitle(
            userBookId: serverUserBookId,
            noteId: null,
            title: note.title,
          );
          if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
            return;
          }
          serverNoteId = result.noteId;
          if (serverNoteId != null) {
            await _dao.confirmNoteCreated(
              localId: localNoteId,
              serverId: serverNoteId,
              capturedUpdatedAt: note.updatedAt,
            );
          }
          developer.log(
            '[노트 생성 push] userBookId=${note.userBookId} '
            'localNoteId=$localNoteId result=SUCCESS',
          );
        } catch (e) {
          developer.log(
            '[노트 생성 push] userBookId=${note.userBookId} '
            'localNoteId=$localNoteId result=FAIL reason=${_reasonOf(e)}',
          );
          // 노트 자체가 아직 서버에 없으니 메모도 보낼 수 없다 — 다음
          // push 때 제목부터 다시 시도한다.
          return;
        }
      }
      // title == null이면 여기서 아무 것도 하지 않는다 — 서버는
      // noteId/title이 모두 없는 PUT을 no-op으로 처리하므로, 아래 메모
      // 루프가 첫 메모로 노트를 함께 만든다.
    } else if (note.isDirty) {
      try {
        await _api.putTitle(
          userBookId: serverUserBookId,
          noteId: serverNoteId,
          title: note.title,
        );
        if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
          return;
        }
        await _dao.confirmNoteTitlePush(
          localId: localNoteId,
          capturedUpdatedAt: note.updatedAt,
        );
        developer.log(
          '[노트 제목 push] userBookId=${note.userBookId} '
          'localNoteId=$localNoteId result=SUCCESS',
        );
      } catch (e) {
        developer.log(
          '[노트 제목 push] userBookId=${note.userBookId} '
          'localNoteId=$localNoteId result=FAIL reason=${_reasonOf(e)}',
        );
        // 노트는 이미 서버에 있으니 제목 push가 실패해도 메모 push는
        // 계속 시도한다(서로 독립적인 필드).
      }
    }

    if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
    await _pushMemosForNote(
      localNoteId,
      serverUserBookId,
      serverNoteId,
      expectedGeneration,
      note.updatedAt,
    );
  }

  /// 소프트 삭제된 노트를 노트 전용 삭제 API로 push한다. 메모 하나가 남긴
  /// 마지막 삭제로 노트까지 함께 삭제 처리된 경우([BookNoteDao.deleteNoteMemo])와
  /// 화면에서 노트 전체를 바로 삭제한 경우([BookNoteDao.deleteNote]) 모두
  /// 여기로 모인다 — 어느 쪽이든 로컬에는 이미 `book_note.deleted_at`만
  /// 찍혀 있고, 메모 행 자체는 push가 끝나야 정리된다.
  Future<void> _pushDeletedNote(
    int userBookId,
    BookNote note,
    int expectedGeneration,
  ) async {
    try {
      if (note.serverId != null) {
        await _api.deleteNote(userBookId: userBookId, noteId: note.serverId!);
      }
      _checkSession(expectedGeneration);
      final memos = await _dao.getAllMemosForNote(note.id);
      for (final memo in memos) {
        await _deleteManagedImage(memo.imageUrl);
      }
      await _dao.purgeNoteAndMemos(note.id);
      developer.log(
        '[노트 삭제 push] userBookId=$userBookId localNoteId=${note.id} '
        'result=SUCCESS',
      );
    } catch (e) {
      developer.log(
        '[노트 삭제 push] userBookId=$userBookId localNoteId=${note.id} '
        'result=FAIL reason=${_reasonOf(e)}',
      );
    }
  }

  Future<int?> _resolveServerUserBookId(int localUserBookId) async {
    var book = await _bookshelfRepository.getById(localUserBookId);
    if (book == null) return null;
    if (book.serverId != null) return book.serverId;
    await _bookshelfRepository.pushDirtyRecord(localUserBookId);
    book = await _bookshelfRepository.getById(localUserBookId);
    return book?.serverId;
  }

  Future<void> _pushMemosForNote(
    int localNoteId,
    int userBookId,
    int? serverNoteId,
    int expectedGeneration,
    DateTime noteUpdatedAt,
  ) async {
    final dirtyMemos = await _dao.getDirtyMemosForNote(localNoteId);
    for (final memo in dirtyMemos) {
      if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
      if (memo.deletedAt != null) {
        await _pushDeletedMemo(userBookId, memo, expectedGeneration);
        continue;
      }
      // 직전 메모의 push가 노트 생성까지는 성공했지만 그 다음 단계(예:
      // PHOTO 승격을 위한 이미지 업로드)에서 실패했을 수 있다 — 그 경우
      // [_pushLiveMemo]의 반환값은 실패로 인해 여전히 null이지만 노트
      // 자체는 이미 서버에 존재한다. serverNoteId가 null일 때마다 DB에서
      // 다시 확인해야 같은 노트를 두 번 만들지 않는다.
      serverNoteId ??= (await _dao.getNoteByLocalId(localNoteId))?.serverId;
      serverNoteId = await _pushLiveMemo(
        userBookId,
        localNoteId,
        serverNoteId,
        memo,
        expectedGeneration,
        noteUpdatedAt,
      );
    }
  }

  Future<void> _pushDeletedMemo(
    int userBookId,
    BookNoteMemo memo,
    int expectedGeneration,
  ) async {
    try {
      if (memo.serverId != null) {
        await _api.deleteNoteMemo(
          userBookId: userBookId,
          noteMemoId: memo.serverId!,
        );
      }
      _checkSession(expectedGeneration);
      await _dao.purgeMemo(memo.id);
      developer.log(
        '[메모 삭제 push] userBookId=$userBookId noteMemoId=${memo.id} '
        'result=SUCCESS',
      );
    } catch (e) {
      developer.log(
        '[메모 삭제 push] userBookId=$userBookId noteMemoId=${memo.id} '
        'result=FAIL reason=${_reasonOf(e)}',
      );
    }
  }

  /// 메모 하나를 push하고, 이 메모가 (제목 없는) 신규 노트를 함께 만들었다면
  /// 그 서버 노트 ID를 반환한다(다음 메모부터는 그 값을 그대로 쓴다).
  Future<int?> _pushLiveMemo(
    int userBookId,
    int localNoteId,
    int? serverNoteId,
    BookNoteMemo memo,
    int expectedGeneration,
    DateTime noteUpdatedAt,
  ) async {
    try {
      if (memo.serverId == null) {
        serverNoteId = await _createMemoOnServer(
          userBookId,
          localNoteId,
          serverNoteId,
          memo,
          expectedGeneration,
          noteUpdatedAt,
        );
      } else {
        await _updateMemoOnServer(
          userBookId,
          serverNoteId!,
          memo,
          expectedGeneration,
        );
      }
      developer.log(
        '[메모 push] userBookId=$userBookId noteMemoId=${memo.id} '
        'result=SUCCESS',
      );
    } catch (e) {
      developer.log(
        '[메모 push] userBookId=$userBookId noteMemoId=${memo.id} '
        'result=FAIL reason=${_reasonOf(e)}',
      );
    }
    return serverNoteId;
  }

  /// [serverNoteId]가 null이면(제목 없는 신규 노트) 이 메모가 노트를 함께
  /// 만든다. PHOTO는 [BookNoteApi.postPhotoNoteMemo] 하나로 노트 생성(필요한
  /// 경우)·사진 저장·메모 생성이 한 요청에서 원자적으로 끝나므로, 중간
  /// 실패로 서버에 반쪽짜리 상태가 남을 걱정이 없다(과거에는 PHOTO를
  /// noteId 없이 만들 수 없어 자리표시용 타입으로 먼저 만든 뒤 PATCH로
  /// 승격하는 우회가 필요했지만, 이 API 추가로 더 이상 필요 없다).
  Future<int> _createMemoOnServer(
    int userBookId,
    int localNoteId,
    int? serverNoteId,
    BookNoteMemo memo,
    int expectedGeneration,
    DateTime noteUpdatedAt,
  ) async {
    final ServerBookNoteMemo created;
    if (memo.type == BookNoteMemoType.photo) {
      final rawPath = _resolveLocalFilePath(memo.imageUrl);
      created = await _api.postPhotoNoteMemo(
        userBookId: userBookId,
        noteId: serverNoteId,
        startPage: memo.startPage,
        endPage: memo.endPage,
        content: memo.content,
        isImportant: memo.isImportant,
        file: File(rawPath),
        clientRequestId: memo.clientRequestId,
      );
    } else {
      created = await _api.postNoteMemo(
        userBookId: userBookId,
        noteId: serverNoteId,
        memoType: memo.type,
        startPage: memo.startPage,
        endPage: memo.endPage,
        content: memo.content,
        isImportant: memo.isImportant,
        clientRequestId: memo.clientRequestId,
      );
    }
    _checkSession(expectedGeneration);
    final newNoteId = created.noteId;
    if (serverNoteId == null) {
      await _confirmNoteBootstrapped(localNoteId, newNoteId, noteUpdatedAt);
    }
    await _confirmMemoAndCleanupImage(memo, created);
    return newNoteId;
  }

  Future<void> _updateMemoOnServer(
    int userBookId,
    int serverNoteId,
    BookNoteMemo memo,
    int expectedGeneration,
  ) async {
    if (memo.type == BookNoteMemoType.photo && _isLocalImage(memo.imageUrl)) {
      final r2Key = await _uploadLocalImage(serverNoteId, memo.imageUrl);
      _checkSession(expectedGeneration);
      final patched = await _api.patchNoteMemo(
        userBookId: userBookId,
        noteMemoId: memo.serverId!,
        memoType: memo.type,
        startPage: memo.startPage,
        endPage: memo.endPage,
        content: memo.content,
        isImportant: memo.isImportant,
        imageUrl: r2Key,
        includeImageUrl: true,
      );
      _checkSession(expectedGeneration);
      await _confirmMemoAndCleanupImage(memo, patched);
      return;
    }
    final patched = await _api.patchNoteMemo(
      userBookId: userBookId,
      noteMemoId: memo.serverId!,
      memoType: memo.type,
      startPage: memo.startPage,
      endPage: memo.endPage,
      content: memo.content,
      isImportant: memo.isImportant,
    );
    _checkSession(expectedGeneration);
    await _confirmMemoAndCleanupImage(memo, patched);
  }

  /// [expectedGeneration]이 이 push를 시작한 시점의 세션과 다르면(그 사이
  /// 로그아웃 등으로 [BookshelfDatabase.clearAll]이 실행됨) 남은 DAO 쓰기를
  /// 모두 건너뛴다. 이 예외는 [_pushLiveMemo]/[_pushDeletedMemo]의
  /// try/catch가 삼켜 로그만 남긴다 — 어차피 로그아웃된 세션의 로컬 행은
  /// 곧 [BookshelfDatabase.clearAll]로 지워지거나, 지워지지 않았더라도 다음
  /// 세션에서 다시 push를 시도하면 그만이라 재시도 자체는 안전하다.
  void _checkSession(int expectedGeneration) {
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      throw const _SessionChanged();
    }
  }

  /// [capturedNoteUpdatedAt]은 이 push 사이클을 시작하기 *직전*(네트워크
  /// 요청 전) [BookNote.updatedAt]이어야 한다. 응답을 받은 뒤 DB를 다시
  /// 읽어 그 값을 쓰면, 마침 이 요청이 오가는 동안 사용자가 같은 노트의
  /// 제목을 새로 입력했을 때 그 "방금 들어온" 값을 "요청 당시 값"으로
  /// 착각해 [BookNoteDao.confirmNoteCreated]의 "변경 없음" 판정을 통과시켜
  /// 버린다 — 실제로는 이번 요청에 전혀 포함되지 않은 새 제목인데도 dirty가
  /// 풀려 영영 push되지 않는다.
  Future<void> _confirmNoteBootstrapped(
    int localNoteId,
    int serverNoteId,
    DateTime capturedNoteUpdatedAt,
  ) async {
    await _dao.confirmNoteCreated(
      localId: localNoteId,
      serverId: serverNoteId,
      capturedUpdatedAt: capturedNoteUpdatedAt,
    );
  }

  Future<void> _confirmMemoAndCleanupImage(
    BookNoteMemo localMemo,
    ServerBookNoteMemo response,
  ) async {
    final applied = await _dao.confirmNoteMemoSynced(
      localId: localMemo.id,
      serverId: response.id,
      capturedUpdatedAt: localMemo.updatedAt,
      memoType: BookNoteMemoType.fromDb(response.memoType),
      startPage: response.startPage,
      endPage: response.endPage,
      content: response.content,
      imageUrl: response.imageUrl,
      isImportant: response.isImportant,
      sortOrder: response.sortOrder,
    );
    // [applied]가 false면(네트워크가 오가는 동안 이 메모가 또 편집돼
    // "변경 없음" 판정에 실패) DB의 image_url은 이 응답 값으로 덮이지
    // 않고 옛 로컬 경로를 그대로 들고 있다 — 그런데도 여기서 파일을
    // 지우면 DB는 이제 존재하지 않는 파일을 계속 가리키게 된다. 실제로
    // DB가 새 원격 URL로 갱신됐을 때만(=이 로컬 파일이 더 이상 어디서도
    // 참조되지 않을 때만) 지운다.
    if (applied &&
        _isLocalImage(localMemo.imageUrl) &&
        localMemo.imageUrl != response.imageUrl) {
      await _deleteManagedImage(localMemo.imageUrl);
    }
  }

  /// 기존 PHOTO 메모의 사진을 교체할 때만 쓴다([_updateMemoOnServer]) —
  /// 새 메모 생성은 [_createMemoOnServer]가 [BookNoteApi.postPhotoNoteMemo]로
  /// 한 번에 처리하므로 이 경로를 타지 않는다.
  Future<String> _uploadLocalImage(int serverNoteId, String? imageUrl) async {
    final rawPath = _resolveLocalFilePath(imageUrl);
    return _api.uploadImage(noteId: serverNoteId, file: File(rawPath));
  }

  String _resolveLocalFilePath(String? imageUrl) {
    if (imageUrl == null) {
      throw const ApiException('업로드할 사진이 없습니다.');
    }
    return imageUrl.startsWith('file://')
        ? Uri.parse(imageUrl).toFilePath()
        : imageUrl;
  }

  bool _isLocalImage(String? url) {
    if (url == null || url.isEmpty) return false;
    return !url.startsWith('http://') && !url.startsWith('https://');
  }

  String _reasonOf(Object error) {
    if (error is _SessionChanged) return 'session_changed';
    if (error is ApiException) return '${error.statusCode ?? "network"}';
    return 'unknown';
  }

  /// 서버(POST .../notes/memos/photo, POST /api/notes/{noteId}/images)가
  /// jpg/jpeg/png/webp·5MB 이하만 허용하므로, 여기서 걸러내지 않으면
  /// 로컬 저장은 성공한 뒤 push가 영원히 400으로 실패하는 메모가 남는다.
  static const _allowedImageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
  static const _maxImageBytes = 5 * 1024 * 1024;

  Future<String?> _resolveImageUrl(BookNoteMemoDraft draft) async {
    if (draft.type != BookNoteMemoType.photo) return null;
    final pickedPath = draft.pickedImagePath;
    if (pickedPath == null) return draft.imageUrl;

    final source = File(pickedPath);
    if (!await source.exists()) throw const FileSystemException();
    final extension = path.extension(pickedPath).toLowerCase();
    if (!_allowedImageExtensions.contains(extension)) {
      throw FileSystemException('지원하지 않는 사진 형식입니다.', pickedPath);
    }
    if (await source.length() > _maxImageBytes) {
      throw FileSystemException('사진 용량은 5MB 이하만 가능합니다.', pickedPath);
    }
    final root = await getApplicationSupportDirectory();
    final directory = Directory(path.join(root.path, 'memo_images'));
    await directory.create(recursive: true);
    final fileName = 'memo_${DateTime.now().microsecondsSinceEpoch}$extension';
    return source
        .copy(path.join(directory.path, fileName))
        .then((file) => file.path);
  }

  Future<void> _deleteManagedImage(String? imageUrl, {String? except}) async {
    if (imageUrl == null || imageUrl.isEmpty || imageUrl == except) return;
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return;
    }

    try {
      final root = await getApplicationSupportDirectory();
      final managedDirectory = path.normalize(
        path.absolute(path.join(root.path, 'memo_images')),
      );
      final rawPath = imageUrl.startsWith('file://')
          ? Uri.parse(imageUrl).toFilePath()
          : imageUrl;
      final targetPath = path.normalize(path.absolute(rawPath));
      if (!path.isWithin(managedDirectory, targetPath)) return;

      final file = File(targetPath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      developer.log('[메모 사진 정리] result=FAIL reason=local_file_error');
    }
  }
}

/// push 진행 중 로그아웃 등으로 세션이 바뀌었을 때 남은 DAO 쓰기를
/// 건너뛰기 위한 내부 신호. [BookNoteRepository._checkSession] 참고.
class _SessionChanged implements Exception {
  const _SessionChanged();
}
