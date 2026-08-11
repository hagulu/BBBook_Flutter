import '../models/book_category.dart';
import '../models/book_item.dart';
import '../models/book_status.dart';
import '../models/book_tag.dart';
import '../models/finished_filter.dart';
import 'book_category_dao.dart';
import 'bookshelf_api.dart';
import 'bookshelf_dao.dart';
import 'bookshelf_database.dart';

/// 책장 기능의 source of truth. 화면은 항상 이 레포지토리를 통해 로컬 DB만
/// 읽고, [sync]를 호출했을 때만 서버와 통신한다.
class BookshelfRepository {
  BookshelfRepository({
    required this._api,
    this._dao = const BookshelfDao(),
    this._categoryDao = const BookCategoryDao(),
  });

  final BookshelfApi _api;
  final BookshelfDao _dao;
  final BookCategoryDao _categoryDao;

  /// 서버 동기화. 로컬에 동기화 기준값(마지막 since)이 없으면(최초 로그인
  /// 또는 로그아웃 후 최초 구성) 전체 동기화를, 있으면 증분 동기화를
  /// 수행한다. 증분 응답이 fullSyncRequired를 반환하면(삭제 이력 유실 가능)
  /// 전체 동기화로 대체한다.
  ///
  /// dirty 로컬 행이 있다면 이 호출 전에 먼저 서버로 push해야 하지만, 이번
  /// 작업 범위엔 책 수정 기능이 없어 dirty 행이 생기지 않으므로 push 단계는
  /// 아직 구현하지 않는다(순서만 확보).
  ///
  /// 반환값은 실제로 로컬 DB가 바뀌었는지 여부. 변경이 없으면 호출 측이
  /// 탭 목록 provider들을 불필요하게 무효화하지 않도록 하기 위함이다.
  ///
  /// 요청 시작 시점의 [BookshelfDatabase.sessionGeneration]을 기억해 두고,
  /// 응답을 받은 뒤 값이 바뀌었으면(그 사이 로그아웃 등으로 [clearLocal]이
  /// 실행됨) 결과를 로컬 DB에 쓰지 않고 버린다. 그러지 않으면 이전 세션의
  /// 응답이 clear 이후 되살아나 다음 로그인 사용자에게 노출될 수 있다.
  Future<bool> sync() async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;

    final since = await _dao.getLastSyncedAt();
    if (since == null) {
      return _fullSync(expectedGeneration);
    }

    final result = await _api.getSyncChanges(since: since);
    if (result.fullSyncRequired) {
      // 증분 응답의 syncedAt(서버 시각)을 기준값으로 쓴다. 클라이언트
      // now()를 쓰면 기기 시계가 서버보다 앞서 있을 때 그 오차만큼 이후
      // 서버 변경을 영구히 놓칠 수 있다.
      return _fullSync(expectedGeneration, baseline: result.syncedAt);
    }

    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }

    // 변경이 없어도 매번 반영한다: 기준값(since)을 항상 앞으로 당겨야
    // 다음 증분 요청이 갈수록 넓어지는 구간을 다시 스캔하지 않는다.
    await _dao.applyChanges(
      upserted: result.upserted,
      deletedUserBookIds: result.deletedUserBookIds,
      syncedAt: result.syncedAt,
    );
    return result.upserted.isNotEmpty || result.deletedUserBookIds.isNotEmpty;
  }

  /// [baseline]을 넘기지 않으면(최초 동기화 등 서버 시각을 알 수 없을 때)
  /// 요청 직전 클라이언트 시각(UTC)을 기준값으로 쓴다.
  Future<bool> _fullSync(int expectedGeneration, {DateTime? baseline}) async {
    final requestedAt = baseline ?? DateTime.now().toUtc();
    final serverItems = await _api.getSync();
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }
    await _dao.reconcile(serverItems, requestedAt);
    return true;
  }

  Future<List<BookItem>> getReadingTab() {
    return _dao.getByStatuses([BookStatus.reading, BookStatus.paused]);
  }

  Future<BookItem?> getById(int userBookId) => _dao.getById(userBookId);

  /// 책 기록 화면에서 서버 PATCH가 성공한 뒤 그 결과를 로컬에 반영한다.
  Future<void> upsertLocal(BookItem item) => _dao.upsertOne(item);

  /// 서재에서 책을 삭제(DELETE API 성공)한 뒤 로컬 행을 제거한다.
  Future<void> deleteLocal(int userBookId) => _dao.deleteOne(userBookId);

  Future<List<BookItem>> getGridTab(BookStatus status) => _dao.getGrid(status);

  Future<List<BookItem>> searchFinished(FinishedFilter filter) =>
      _dao.searchFinished(filter);

  Future<List<String>> getDistinctCategories() => _dao.getDistinctCategories();

  Future<List<String>> getDistinctDifficulties() =>
      _dao.getDistinctDifficulties();

  Future<List<BookTag>> getDistinctTags() => _dao.getDistinctTags();

  Future<DateTime?> getLastSyncedAt() => _dao.getLastSyncedAt();

  Future<bool> getPrivacySetting() => _api.getPrivacySetting();

  Future<bool> setPrivacySetting(bool isFinishedBooksPublic) {
    return _api.patchPrivacySetting(
      isFinishedBooksPublic: isFinishedBooksPublic,
    );
  }

  /// 로그아웃 시 다음 사용자에게 이전 계정의 책장이 보이지 않도록 로컬 DB를 비운다.
  Future<void> clearLocal() => BookshelfDatabase.clearAll();

  /// 카테고리 마스터 목록. 로컬 캐시가 있으면(계정 무관 데이터라 로그아웃해도
  /// 유지됨) 그대로 반환하고, 없으면 서버에서 받아와 캐시를 채운 뒤 반환한다.
  Future<List<BookCategory>> getCategories() async {
    final cached = await _categoryDao.getAll();
    if (cached.isNotEmpty) return cached;
    return refreshCategories();
  }

  /// 로그인 시 호출: 캐시 유무와 상관없이 서버에서 다시 받아와 로컬 캐시를
  /// 통째로 교체한다. 카테고리는 세션 내내 캐시만 쓰므로(주기적 재조회 없음)
  /// staleness를 "로그인 시점"으로만 한정하기 위함이다.
  Future<List<BookCategory>> refreshCategories() async {
    final categories = await _api.getCategories();
    if (categories.isNotEmpty) {
      await _categoryDao.replaceAll(categories);
    }
    return categories;
  }
}
