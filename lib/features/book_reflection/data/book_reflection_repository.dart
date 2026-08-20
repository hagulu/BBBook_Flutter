import '../../bookshelf/data/bookshelf_database.dart';
import '../../record_sync/data/record_sync_api.dart';
import '../models/book_reflection.dart';
import 'book_reflection_api.dart';
import 'book_reflection_dao.dart';

/// 독후감 화면의 source of truth.
///
/// 화면은 항상 이 Repository를 통해 로컬 DB만 읽는다([BookMemoRepository]와
/// 같은 원칙). 아직 로컬 생성/수정/삭제(편집기) 기능이 없어 dirty push
/// 경로는 없고, [sync]는 서버 조회 결과를 로컬에 반영하는 읽기 전용
/// 동기화만 수행한다 — 편집기를 붙일 때 [BookMemoRepository]의 dirty push
/// 패턴을 그대로 이식하면 된다.
class BookReflectionRepository {
  BookReflectionRepository({
    required this._api,
    required this._recordSyncApi,
    this._dao = const BookReflectionDao(),
  });

  final BookReflectionApi _api;
  final RecordSyncApi _recordSyncApi;
  final BookReflectionDao _dao;

  Future<List<BookReflection>> findByUserBook({
    required int ownerUserId,
    required int userBookId,
  }) {
    return _dao.findByUserBook(ownerUserId: ownerUserId, userBookId: userBookId);
  }

  Future<BookReflection?> findDetail({
    required int ownerUserId,
    required int userBookId,
    required int reflectionId,
  }) {
    return _dao.findDetail(
      ownerUserId: ownerUserId,
      userBookId: userBookId,
      reflectionId: reflectionId,
    );
  }

  // ---------------------------------------------------------------------
  // 서버 동기화
  // ---------------------------------------------------------------------

  Future<DateTime?> getLastSyncedAtReflection() =>
      _dao.getLastSyncedAtReflection();

  /// since가 없으면 전체 동기화, 있으면 증분 동기화 → 증분 응답이
  /// fullSyncRequired면 전체 동기화로 대체. [BookMemoRepository.sync]와
  /// 같은 구조(단, dirty push 단계가 없다).
  ///
  /// 반환값은 실제로 로컬 DB가 바뀌었는지 여부.
  Future<bool> sync({required int ownerUserId}) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;

    final since = await _dao.getLastSyncedAtReflection();
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

    await _dao.applyReflectionChanges(
      ownerUserId: ownerUserId,
      upsertedReflections: result.upsertedReflections,
      deletedReflectionIds: result.deletedReflectionIds,
      syncedAt: result.syncedAt,
    );
    return result.upsertedReflections.isNotEmpty ||
        result.deletedReflectionIds.isNotEmpty;
  }

  /// [baseline]을 넘기지 않으면(최초 동기화 등 서버 시각을 알 수 없을 때)
  /// 요청 직전 클라이언트 시각(UTC)을 기준값으로 쓴다. `/api/me/records`(최초
  /// 기록 전체 조회 — record_sync 기능과 같은 API)를 그대로 재사용한다.
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
    await _dao.reconcileFullReflection(
      ownerUserId: ownerUserId,
      activeUserBookIds: payload.books
          .map((b) => b.userBookId)
          .toList(growable: false),
      reflections: payload.reflections,
      requestedAt: requestedAt,
    );
    return true;
  }
}
