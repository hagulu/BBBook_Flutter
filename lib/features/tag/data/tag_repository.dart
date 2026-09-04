import 'dart:async';
import 'dart:developer' as developer;

import '../../../core/network/api_exception.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../bookshelf/data/bookshelf_repository.dart';
import '../../record_sync/data/record_sync_api.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import 'tag_api.dart';
import 'tag_dao.dart';

/// 태그 화면(책 기록 상세의 태그 섹션)의 source of truth.
///
/// [addTag]/[removeTag]는 로컬에 즉시 반영하고([TagDao]) `is_dirty = 1`로
/// 표시한 뒤 그 자리에서 조용히 서버로 push를 시도한다([pushMapping]) —
/// 성공하면 dirty가 풀리고, 실패(오프라인 등)하면 dirty가 남아 다음 [sync]
/// 호출 때 재시도된다. `BookNoteRepository`/`BookshelfRepository`와 같은
/// 로컬 우선 구조다.
///
/// [sync]는 dirty push를 먼저 처리한 뒤, 로컬에 동기화 기준값(마지막 since)이
/// 없으면(최초 로그인 등) 전체 동기화(`/api/me/records`)를, 있으면 증분
/// 동기화(`/api/me/tags/sync/changes`)를 수행한다. 태그/매핑은 계정 전체
/// 단위라(책 하나에 매이지 않음) `ownerUserId`를 따로 받지 않는다
/// (`BookshelfRepository.sync`와 같은 구조 — `tag`/`user_book_tag_map`
/// 테이블에 소유자 컬럼이 없는 이유도 `user_book`과 동일하다).
class TagRepository {
  TagRepository({
    required this._api,
    required this._recordSyncApi,
    required this._bookshelfRepository,
    this._dao = const TagDao(),
    StorageModeStore? storageMode,
  }) : _storageMode = storageMode ?? storageModeStore;

  final TagApi _api;
  final RecordSyncApi _recordSyncApi;
  final BookshelfRepository _bookshelfRepository;
  final TagDao _dao;
  final StorageModeStore _storageMode;

  /// [pushMapping] 호출을 매핑별로 순서대로 실행시키는 체인
  /// (`BookNoteRepository._dirtyPushChains`와 같은 이유).
  final Map<int, Future<void>> _dirtyPushChains = {};

  Future<void> addTag({required int userBookId, required String name}) async {
    final localMappingId = await _dao.addTagLocal(
      userBookId: userBookId,
      name: name,
    );
    unawaited(pushMapping(localMappingId));
  }

  Future<void> removeTag({
    required int userBookId,
    required int tagLocalId,
  }) async {
    final localMappingId = await _dao.removeTagLocal(
      userBookId: userBookId,
      tagLocalId: tagLocalId,
    );
    if (localMappingId != null) unawaited(pushMapping(localMappingId));
  }

  // ---------------------------------------------------------------------
  // 서버 동기화
  // ---------------------------------------------------------------------

  Future<DateTime?> getLastSyncedAtTag() => _dao.getLastSyncedAtTag();

  Future<bool> sync() async {
    if (await _storageMode.isLocal()) return false;
    final expectedGeneration = BookshelfDatabase.sessionGeneration;

    await pushAllDirty();
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }

    final since = await _dao.getLastSyncedAtTag();
    if (since == null) return _fullSync(expectedGeneration);

    final result = await _api.getSyncChanges(since: since);
    if (result.fullSyncRequired) {
      return _fullSync(expectedGeneration, baseline: result.syncedAt);
    }
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }

    await _dao.applyTagChanges(
      upsertedTags: result.upsertedTags,
      deletedTagIds: result.deletedTagIds,
      upsertedTagMaps: result.upsertedTagMaps,
      deletedTagMapIds: result.deletedTagMapIds,
      syncedAt: result.syncedAt,
    );
    return result.upsertedTags.isNotEmpty ||
        result.deletedTagIds.isNotEmpty ||
        result.upsertedTagMaps.isNotEmpty ||
        result.deletedTagMapIds.isNotEmpty;
  }

  Future<bool> _fullSync(int expectedGeneration, {DateTime? baseline}) async {
    final requestedAt = baseline ?? DateTime.now().toUtc();
    final payload = await _recordSyncApi.getAllRecords();
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }
    await _dao.reconcileFullTags(
      activeServerUserBookIds: payload.books
          .map((b) => b.userBookId)
          .toList(growable: false),
      tags: payload.tags,
      tagMaps: payload.tagMaps,
      requestedAt: requestedAt,
    );
    return true;
  }

  /// dirty 표시된 매핑을 모두 서버로 일괄 재전송한다. 각 매핑은 독립적으로
  /// 처리한다 — 하나가 실패해도 다른 매핑의 push는 계속 시도한다.
  Future<void> pushAllDirty() async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final ids = await _dao.getDirtyMappingLocalIds();
    for (final id in ids) {
      if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
      await pushMapping(id);
    }
  }

  Future<void> pushMapping(int localMappingId) {
    final previous = _dirtyPushChains[localMappingId] ?? Future<void>.value();
    final chained = previous
        .then((_) => _pushOneMapping(localMappingId))
        .catchError((_, _) {});
    _dirtyPushChains[localMappingId] = chained;
    return chained;
  }

  Future<void> _pushOneMapping(int localMappingId) async {
    if (await _storageMode.isLocal()) return;
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final mapping = await _dao.getMappingByLocalId(localMappingId);
    if (mapping == null || !mapping.isDirty) return;
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;

    final serverUserBookId = await _resolveServerUserBookId(mapping.userBookId);
    if (serverUserBookId == null) {
      developer.log(
        '[태그 매핑 push] localUserBookId=${mapping.userBookId} '
        'result=FAIL reason=book_create_pending',
      );
      return;
    }

    if (mapping.deletedAt != null) {
      await _pushDeletedMapping(
        serverUserBookId,
        mapping.id,
        mapping.tagId,
        expectedGeneration,
      );
      return;
    }
    await _pushCreatedMapping(
      serverUserBookId,
      mapping.id,
      mapping.tagId,
      mapping.updatedAt,
      expectedGeneration,
    );
  }

  Future<int?> _resolveServerUserBookId(int localUserBookId) async {
    var book = await _bookshelfRepository.getById(localUserBookId);
    if (book == null) return null;
    if (book.serverId != null) return book.serverId;
    await _bookshelfRepository.pushDirtyRecord(localUserBookId);
    book = await _bookshelfRepository.getById(localUserBookId);
    return book?.serverId;
  }

  Future<void> _pushCreatedMapping(
    int serverUserBookId,
    int mappingLocalId,
    int pendingTagLocalId,
    DateTime capturedUpdatedAt,
    int expectedGeneration,
  ) async {
    final tag = await _dao.getTagByLocalId(pendingTagLocalId);
    if (tag == null) {
      // 참조하는 태그 행이 사라진 비정상 상태 — 더는 유효하지 않으니 정리한다.
      await _dao.purgeMapping(mappingLocalId);
      return;
    }
    try {
      final result = await _api.postTag(
        userBookId: serverUserBookId,
        name: tag.name,
      );
      if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
      await _dao.confirmMappingCreated(
        mappingLocalId: mappingLocalId,
        capturedUpdatedAt: capturedUpdatedAt,
        pendingTagLocalId: pendingTagLocalId,
        serverTagId: result.id,
        serverTagName: result.name,
      );
      developer.log(
        '[태그 매핑 생성 push] userBookId=$serverUserBookId '
        'mappingId=$mappingLocalId result=SUCCESS',
      );
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        // 서버에는 이미 활성 매핑이 있다(이전 시도의 응답만 못 받았거나
        // 다른 기기가 먼저 추가함). 정확한 서버 tagId는 곧 이어질 증분
        // 동기화의 upsertedTags/upsertedTagMaps가 채워준다
        // (`TagDao._upsertServerTagMapTxn`) — dirty는 그대로 두어도 안전하다
        // (그때까지 재시도해도 서버가 다시 무해하게 409로 답할 뿐이다).
        developer.log(
          '[태그 매핑 생성 push] userBookId=$serverUserBookId '
          'mappingId=$mappingLocalId result=SKIP reason=already_active',
        );
        return;
      }
      developer.log(
        '[태그 매핑 생성 push] userBookId=$serverUserBookId '
        'mappingId=$mappingLocalId result=FAIL reason=${e.statusCode ?? "network"}',
      );
    }
  }

  Future<void> _pushDeletedMapping(
    int serverUserBookId,
    int mappingLocalId,
    int tagLocalId,
    int expectedGeneration,
  ) async {
    final tag = await _dao.getTagByLocalId(tagLocalId);
    final serverTagId = tag?.serverId;
    if (serverTagId == null) {
      // 생성~삭제가 전부 오프라인에서 끝나 서버가 이 매핑을 알 길이 없었다
      // — 알릴 것이 없으므로 바로 정리한다.
      await _dao.purgeMapping(mappingLocalId);
      return;
    }
    try {
      await _api.deleteTag(userBookId: serverUserBookId, tagId: serverTagId);
      if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
      await _dao.purgeMapping(mappingLocalId);
      developer.log(
        '[태그 매핑 삭제 push] userBookId=$serverUserBookId '
        'mappingId=$mappingLocalId result=SUCCESS',
      );
    } on ApiException catch (e) {
      developer.log(
        '[태그 매핑 삭제 push] userBookId=$serverUserBookId '
        'mappingId=$mappingLocalId result=FAIL reason=${e.statusCode ?? "network"}',
      );
    }
  }
}
