import 'dart:io';

import '../../../core/network/api_exception.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../bookshelf/data/bookshelf_repository.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/models/book_tag.dart';
import 'book_record_api.dart';

/// 책 기록 상세 화면의 source of truth. 조회는 [BookshelfRepository]의 로컬
/// DB만 사용하고, 수정은 [BookRecordApi]로 서버 PATCH가 성공한 뒤에만 그
/// 결과를 로컬 DB에 반영한다(서버가 최종 진실 소스 — 서버 실패 시 로컬은
/// 건드리지 않는다).
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

  Future<BookItem> updateRecord(
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
    final current = await _requireLocal(userBookId);
    final data = await _api.patchRecord(
      userBookId: userBookId,
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
    );
    return _persist(current, data, expectedGeneration);
  }

  Future<BookItem> updateBookInfo(
    int userBookId, {
    required String title,
    String? author,
    String? publisher,
    int? totalPages,
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

  /// PATCH류 응답(`createdAt`/`updatedAt` 없음)을 [current]의 createdAt과
  /// 현재 클라이언트 시각(UTC)으로 보강해 로컬 DB에 반영한다. [expectedGeneration]이
  /// 호출 시점과 달라졌으면(로그아웃 등) 로컬에 쓰지 않는다.
  Future<BookItem> _persist(
    BookItem current,
    Map<String, dynamic> data,
    int expectedGeneration,
  ) async {
    final updated = BookItem.fromDetailJson(
      data,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    if (BookshelfDatabase.sessionGeneration == expectedGeneration) {
      await _bookshelfRepository.upsertLocal(updated);
    }
    return updated;
  }
}
