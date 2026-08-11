import 'dart:async';
import 'dart:io';

import '../../../core/network/api_exception.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../bookshelf/data/bookshelf_repository.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/models/book_tag.dart';
import 'book_record_api.dart';

/// 책 기록 상세 화면의 source of truth. 조회는 [BookshelfRepository]의 로컬
/// DB만 사용한다.
///
/// [updateRecord](기본 기록 필드 — `PATCH /api/me/books/:userBookId`)는 로컬
/// 우선이다: 즉시 로컬에 반영해 반환하고, 서버 반영은 뒤에서 조용히
/// 시도한다 — 실패해도 예외를 던지지 않고 dirty로 남겨 다음 동기화
/// (`BookshelfRepository.sync()`)가 일괄 재시도하게 한다. 그 외
/// [updateBookInfo]/[addTag]/[removeTag]/[deleteBook]은 여전히 서버 PATCH가
/// 성공한 뒤에만 로컬에 반영한다(서버가 최종 진실 소스 — 서버 실패 시
/// 로컬은 건드리지 않고 예외를 던져 화면이 에러를 처리하게 한다).
///
/// 각 쓰기 메서드는 API 호출 *전* [BookshelfDatabase.sessionGeneration]을
/// 기억해 뒀다가, 응답을 받은 뒤 값이 바뀌었으면(그사이 로그아웃 등으로
/// [BookshelfDatabase.clearAll]이 실행됨) 로컬 DB에 쓰지 않고 결과를 버린다.
/// `BookshelfRepository.sync()`가 증분/전체 동기화에 쓰는 것과 동일한
/// 보호 장치다 — 그러지 않으면 로그아웃 직전에 시작된 PATCH/삭제 응답이
/// 늦게 도착했을 때 방금 비운 DB에 이전 계정의 책을 다시 채워 넣을 수 있다.
class BookRecordRepository {
  BookRecordRepository({
    required this._api,
    required this._bookshelfRepository,
  });

  final BookRecordApi _api;
  final BookshelfRepository _bookshelfRepository;

  Future<BookItem?> getLocal(int userBookId) =>
      _bookshelfRepository.getById(userBookId);

  /// 로컬에 즉시 반영하고 그 결과를 반환한다. 서버 반영은 기다리지 않고
  /// [BookshelfRepository.pushDirtyRecord]로 뒤에서 조용히 시도한다 —
  /// 실패해도 이 메서드는 예외를 던지지 않는다(호출부인
  /// [BookRecordController]가 로딩/에러 UI 없이 즉시 반영된 것처럼
  /// 보여줘야 하므로). push 자체의 스냅샷 구성·경합 처리·재시도 정책은
  /// [BookshelfRepository.pushDirtyRecord]가 전담한다 — 책 기록 화면에서의
  /// 즉시 push와 동기화 시점의 일괄 재시도가 같은 로직을 공유해야, 두
  /// 경로가 동시에 실행돼도(연속 편집 도중 앱이 포그라운드로 전환되는 등)
  /// 서로의 결과를 덮어쓰지 않는다.
  ///
  /// 로컬 행이 없으면(다른 기기에서 이미 삭제됨 등) 아무 것도 하지 않고
  /// null을 반환한다 — 존재하지 않는 책을 오프라인 편집으로 되살릴 수는
  /// 없다.
  Future<BookItem?> updateRecord(
    int userBookId, {
    String? status,
    int? currentPage,
    double? myRating,
    String? shortReview,
    bool? isMasterpiece,
    String? sourceType,
    int? rereadCount,
    String? difficulty,
    String? startedAt,
    String? finishedAt,
    String? platformName,
    String? discoverySource,
  }) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final current = await _bookshelfRepository.getById(userBookId);
    if (current == null) return null;

    final merged = current.copyWithRecord(
      status: status,
      currentPage: currentPage,
      myRating: myRating,
      shortReview: shortReview,
      isMasterpiece: isMasterpiece,
      sourceType: sourceType,
      rereadCount: rereadCount,
      difficulty: difficulty,
      startedAt: startedAt,
      finishedAt: finishedAt,
      platformName: platformName,
      discoverySource: discoverySource,
      updatedAt: DateTime.now().toUtc(),
    );

    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return null;
    }
    await _bookshelfRepository.applyLocalEdit(merged);

    unawaited(_bookshelfRepository.pushDirtyRecord(userBookId));

    return merged;
  }

  Future<BookItem> updateBookInfo(
    int userBookId, {
    required String title,
    String? author,
    String? publisher,
    int? totalPages,
    int? categoryId,
    File? thumbnailFile,
    bool removeThumbnail = false,
  }) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final current = await _requireLocal(userBookId);
    final data = await _api.patchBookInfo(
      userBookId: userBookId,
      title: title,
      author: author,
      publisher: publisher,
      totalPages: totalPages,
      categoryId: categoryId,
      thumbnailFile: thumbnailFile,
      removeThumbnail: removeThumbnail,
    );
    return _persist(current, data, expectedGeneration);
  }

  /// 태그 추가. 서버는 태그 정보(id/name)만 반환하므로, 로컬 행에는 기존
  /// 태그 목록에 새 태그를 더해 반영한다.
  Future<BookItem> addTag(int userBookId, String name) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final current = await _requireLocal(userBookId);
    final tag = await _api.postTag(userBookId: userBookId, name: name);
    final updated = current.copyWithTags([
      ...current.tags,
      tag,
    ], updatedAt: DateTime.now().toUtc());
    if (BookshelfDatabase.sessionGeneration == expectedGeneration) {
      await _bookshelfRepository.upsertLocal(updated);
    }
    return updated;
  }

  Future<BookItem> removeTag(int userBookId, int tagId) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final current = await _requireLocal(userBookId);
    await _api.deleteTag(userBookId: userBookId, tagId: tagId);
    final updated = current.copyWithTags(
      current.tags.where((t) => t.id != tagId).toList(),
      updatedAt: DateTime.now().toUtc(),
    );
    if (BookshelfDatabase.sessionGeneration == expectedGeneration) {
      await _bookshelfRepository.upsertLocal(updated);
    }
    return updated;
  }

  Future<List<BookTag>> getTagSuggestions() => _api.getMyTags();

  Future<Map<String, List<String>>> getPlatformOptions() =>
      _api.getPlatformOptions();

  Future<void> deleteBook(int userBookId) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    await _api.deleteUserBook(userBookId);
    if (BookshelfDatabase.sessionGeneration == expectedGeneration) {
      await _bookshelfRepository.deleteLocal(userBookId);
    }
  }

  /// 화면이 열려 있는 동안 백그라운드 동기화가 이 책을 로컬에서 지웠을 수
  /// 있다(예: 다른 기기에서 삭제). UI는 [ApiException]만 잡아 스낵바로
  /// 보여주므로 같은 타입으로 던진다.
  Future<BookItem> _requireLocal(int userBookId) async {
    final item = await _bookshelfRepository.getById(userBookId);
    if (item == null) {
      throw const ApiException('존재하지 않거나 이미 삭제된 책입니다.');
    }
    return item;
  }

  /// 책 정보 PATCH 응답(`createdAt` 없음, `updatedAt`은 있음 — api-doc)을
  /// [current]의 createdAt으로 보강해 로컬 DB에 반영한다. 응답의 `updatedAt`은
  /// 실제 서버 값이라 [BookshelfRepository.upsertLocal]에 충돌 검사
  /// 기준값으로 함께 넘긴다 — 그러지 않으면 이 책 정보 수정으로 서버의
  /// `user_book.updated_at`이 바뀐 뒤에도 로컬은 이전 기준값을 그대로 들고
  /// 있어, 다음 기록 필드 PATCH가 실제로는 최신인데도 409로 거부될 수 있다.
  /// [expectedGeneration]이 호출 시점과 달라졌으면(로그아웃 등) 로컬에
  /// 쓰지 않는다.
  Future<BookItem> _persist(
    BookItem current,
    Map<String, dynamic> data,
    int expectedGeneration,
  ) async {
    final updated = BookItem.fromDetailJson(data, createdAt: current.createdAt);
    if (BookshelfDatabase.sessionGeneration == expectedGeneration) {
      await _bookshelfRepository.upsertLocal(
        updated,
        syncedUpdatedAt: updated.updatedAt,
      );
    }
    return updated;
  }
}
