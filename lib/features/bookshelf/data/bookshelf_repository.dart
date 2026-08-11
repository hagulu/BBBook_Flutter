import 'dart:developer' as developer;

import '../../../core/network/api_exception.dart';
import '../../book_record/data/book_record_api.dart';
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
    required this._recordApi,
    this._dao = const BookshelfDao(),
    this._categoryDao = const BookCategoryDao(),
  });

  final BookshelfApi _api;
  final BookRecordApi _recordApi;
  final BookshelfDao _dao;
  final BookCategoryDao _categoryDao;

  /// [pushDirtyRecord] 호출을 책별로 순서대로 실행시키는 체인. 겹치는 호출이
  /// 동시에 같은 baseline으로 push를 보내면 서버가 뒤에 도착한 요청을 (실제
  /// 충돌이 아닌데도) 409로 거부해 그 로컬 편집을 잃을 수 있다 — 자세한
  /// 내용은 [pushDirtyRecord] 참고.
  final Map<int, Future<void>> _dirtyPushChains = {};

  /// 서버 동기화. dirty 로컬 행(책 기록 화면에서 로컬 우선 반영한 뒤 아직
  /// 서버에 반영되지 못한 수정)이 있으면 먼저 일괄 push한 뒤, 로컬에 동기화
  /// 기준값(마지막 since)이 없으면(최초 로그인 또는 로그아웃 후 최초 구성)
  /// 전체 동기화를, 있으면 증분 동기화를 수행한다. 증분 응답이
  /// fullSyncRequired를 반환하면(삭제 이력 유실 가능) 전체 동기화로 대체한다.
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

    await _pushDirtyRecords(expectedGeneration);
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }

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

  /// dirty 표시된 책 기록 로컬 수정을 서버로 일괄 재전송한다(오프라인/실패로
  /// 아직 반영되지 못한 것들 — 책 기록 화면에서 편집 직후 시도하는
  /// [pushDirtyRecord]와 같은 책별 큐를 공유한다). 그러지 않고 이 행들을
  /// 직접 push하면, 마침 그 책을 편집 중이던 화면의 즉시 push와 여기서의
  /// push가 동시에 나가 서로의 결과를 덮어쓸 수 있다(연속 편집 유실과
  /// 동일한 경합 — [pushDirtyRecord] 참고).
  ///
  /// 각 행은 독립적으로 처리한다 — 한 행이 실패해도(네트워크 오류 등) 다른
  /// 행들의 push는 계속 시도하고, dirty가 남은 행은 다음 동기화 때 다시
  /// 재시도된다.
  Future<void> _pushDirtyRecords(int expectedGeneration) async {
    final dirty = await _dao.getDirtyRecords();
    for (final (item, _) in dirty) {
      if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
      await pushDirtyRecord(item.userBookId);
    }
  }

  /// 특정 책의 dirty 로컬 편집을 서버로 push한다. 책 기록 화면의 편집 직후
  /// 즉시 호출([BookRecordRepository.updateRecord])되기도 하고, 동기화
  /// 시점([_pushDirtyRecords])에도 호출된다 — 두 경로가 겹쳐도(연속 편집
  /// 도중 앱이 포그라운드로 전환돼 동기화가 도는 등) 안전하도록 같은 책에
  /// 대한 모든 호출을 [_dirtyPushChains]로 한 줄로 세운다. 그러지 않으면
  /// 두 요청이 같은 `synced_updated_at` 기준값으로 동시에 나가고, 서버에
  /// 먼저 도착한 요청만 성공하며 나중 요청은 (실제로는 우리 자신의 앞선
  /// 요청 때문에 바뀐) 최신 updated_at과 비교돼 진짜 충돌이 아닌데도 409로
  /// 거부된다 — 그 결과가 [BookshelfDao.resolveConflict]로 이어지면 방금
  /// 성공한 편집까지 서버 상태로 되돌아갈 수 있다.
  ///
  /// 매 호출마다 실행 시점의 최신 dirty 행을 다시 읽는다(호출 시점의
  /// 스냅샷을 들고 있지 않음) — 그래야 대기 중이던 호출이 실제로 실행될
  /// 때 그 사이 쌓인 편집까지 포함해서 보낸다. dirty가 아니면(이미 push가
  /// 끝났으면) 아무 것도 하지 않는다.
  Future<void> pushDirtyRecord(int userBookId) {
    final previous = _dirtyPushChains[userBookId] ?? Future<void>.value();
    final chained = previous
        .then((_) => _pushOneDirtyRecord(userBookId))
        // 체인에 쌓인 Future가 에러로 완료되면 그 뒤에 이어붙는 호출들이
        // 전부 건너뛰어지므로 여기서 삼켜 체인이 끊기지 않게 한다(실패는
        // 이미 [_pushDirtyItem] 내부에서 로그로만 남기고 dirty를 유지한다).
        .catchError((_, _) {});
    _dirtyPushChains[userBookId] = chained;
    return chained;
  }

  /// 실행 시점(대기열에서 순서가 왔을 때)의 최신 세션 generation과 dirty
  /// 상태를 기준으로 한다 — 큐에 오래 대기했을 수 있어 호출 시점 값을
  /// 넘겨받지 않고 여기서 새로 읽는다.
  Future<void> _pushOneDirtyRecord(int userBookId) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final dirty = await _dao.getDirtyRecord(userBookId);
    if (dirty == null) return;
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
    await _pushDirtyItem(dirty.$1, dirty.$2, expectedGeneration);
  }

  /// dirty 행 한 건을 서버로 push한다. 이 행이 현재 로컬에 들고 있는 필드
  /// 전체를 스냅샷으로 보낸다(어떤 필드가 바뀌었는지 별도로 추적하지 않음)
  /// — null이면 "변경 없음"인 API 의미상 안전하다(로컬 null은 원래 미설정
  /// 상태이므로 그대로 보내면 "변경 없음"과 같은 뜻이 된다).
  /// platformName/discoverySource도 로컬 null을 그대로 보낸다: 빈 문자열로
  /// 바꿔 보내면 "미설정 상태를 유지"가 아니라 "명시적으로 지움"이 되어,
  /// 애초에 값이 없던 행까지 서버 값을 지워버릴 수 있다(예: sourceType이
  /// EBOOK인데 platformName을 아직 한 번도 설정하지 않은 행). status가
  /// FINISHED인데 finishedAt을 모르면, status까지 같이 보낼 때 서버가
  /// 완독일을 오늘 날짜로 새로 잡아버린다 — 그 조합일 때만 status를
  /// 생략한다([BookItem.copyWithRecord]가 최초 완독 전환 시 로컬에도 곧바로
  /// 오늘 날짜를 채워 두므로 정상 흐름에서는 이 조합 자체가 드물다).
  ///
  /// 성공하면 이 push를 보낸 뒤로 로컬 행이 더 바뀌지 않았을 때만(요청을
  /// 만들 때 읽은 [item.updatedAt]과 현재 로컬 값이 같을 때만) 응답으로
  /// 확정 반영하고 dirty를 해제한다. 그 사이 새 로컬 편집이 쌓였으면(이
  /// 네트워크 요청이 오가는 동안 사용자가 같은 책을 또 편집하는 경우 — 같은
  /// 책에 대한 push 자체는 [pushDirtyRecord]의 큐로 직렬화되지만, 로컬 편집
  /// 자체는 그 큐를 기다리지 않고 즉시 반영되므로 이 창구는 여전히 남는다)
  /// 그 편집을 덮어쓰면 안 되므로 필드는 그대로 두고 충돌 검사 기준값만
  /// 이번 응답의 서버 updated_at으로 갱신한다 — dirty는 남아 다음 push가
  /// 최신 상태를 다시 보낸다.
  Future<void> _pushDirtyItem(
    BookItem item,
    DateTime? baseUpdatedAt,
    int expectedGeneration,
  ) async {
    try {
      final data = await _recordApi.patchRecord(
        userBookId: item.userBookId,
        status: (item.status == BookStatus.finished && item.finishedAt == null)
            ? null
            : item.status.apiValue,
        currentPage: item.currentPage,
        myRating: item.myRating,
        shortReview: item.shortReview,
        isMasterpiece: item.isMasterpiece,
        sourceType: item.sourceType,
        rereadCount: item.rereadCount,
        difficulty: item.difficulty,
        startedAt: _formatDate(item.startedAt),
        finishedAt: _formatDate(item.finishedAt),
        platformName: item.platformName,
        discoverySource: item.discoverySource,
        updatedAt: baseUpdatedAt,
      );
      if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;

      final latest = await _dao.getById(item.userBookId);
      if (latest == null) {
        // push가 오가는 사이 이 책이 로컬에서 사라졌다(동시 삭제 등) —
        // 확정 반영을 건너뛴다(이미 지워진 책을 되살리지 않도록).
        return;
      }

      final serverItem = BookItem.fromDetailJson(data, createdAt: item.createdAt);
      if (latest.updatedAt == item.updatedAt) {
        await _dao.confirmPush(serverItem);
      } else {
        await _dao.refreshSyncedUpdatedAt(item.userBookId, serverItem.updatedAt);
      }
      developer.log(
        '[책 기록 더티 push] userBookId=${item.userBookId} result=SUCCESS',
      );
    } on ApiException catch (e) {
      if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
      if (e.statusCode == 409) {
        await _dao.resolveConflict(item.userBookId);
        developer.log(
          '[책 기록 더티 push] userBookId=${item.userBookId} result=FAIL reason=conflict',
        );
      } else {
        developer.log(
          '[책 기록 더티 push] userBookId=${item.userBookId} result=FAIL reason=${e.statusCode ?? "network"}',
        );
      }
    } catch (e) {
      developer.log(
        '[책 기록 더티 push] userBookId=${item.userBookId} result=FAIL reason=unknown',
      );
    }
  }

  String? _formatDate(DateTime? date) =>
      date?.toIso8601String().substring(0, 10);

  Future<List<BookItem>> getReadingTab() {
    return _dao.getByStatuses([BookStatus.reading, BookStatus.paused]);
  }

  Future<BookItem?> getById(int userBookId) => _dao.getById(userBookId);

  /// 책 기록 화면에서 서버 PATCH가 성공한 뒤 그 결과를 로컬에 반영한다.
  /// [syncedUpdatedAt]은 응답에 실제 서버 updated_at이 함께 내려오는
  /// 호출(책 정보 PATCH)만 넘긴다 — [BookshelfDao.upsertOne] 참고.
  Future<void> upsertLocal(BookItem item, {DateTime? syncedUpdatedAt}) =>
      _dao.upsertOne(item, syncedUpdatedAt: syncedUpdatedAt);

  /// 서재에서 책을 삭제(DELETE API 성공)한 뒤 로컬 행을 제거한다.
  Future<void> deleteLocal(int userBookId) => _dao.deleteOne(userBookId);

  /// 책 기록 화면의 필드 수정을 로컬에 즉시 반영하고 dirty로 표시한다.
  /// 서버 반영은 호출부가 이어서 [pushDirtyRecord]로 트리거한다.
  Future<void> applyLocalEdit(BookItem item) => _dao.applyLocalEdit(item);

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
