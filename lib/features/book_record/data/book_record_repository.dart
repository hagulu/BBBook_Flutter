import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import '../../../core/network/api_exception.dart';
import '../../book_search/models/book_search_item.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../bookshelf/data/bookshelf_repository.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/models/book_tag.dart';
import '../../bookshelf/models/record_patch.dart';
import '../../bookshelf/services/book_cover_image_store.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import 'book_record_api.dart';

/// 책 기록 상세 화면의 source of truth. 조회는 [BookshelfRepository]의 로컬
/// DB만 사용한다.
///
/// [updateRecord](기본 기록 필드 — `PATCH /api/me/books/:userBookId`)는 로컬
/// 우선이다: 즉시 로컬에 반영해 반환하고, 서버 반영은 뒤에서 조용히
/// 시도한다 — 실패해도 예외를 던지지 않고 dirty로 남겨 다음 동기화
/// (`BookshelfRepository.sync()`)가 일괄 재시도하게 한다. 그 외
/// [updateBookInfo]/[linkBook]/[addTag]/[removeTag]/[deleteBook]은 여전히 서버 PATCH가
/// 성공한 뒤에만 로컬에 반영한다(서버가 최종 진실 소스 — 서버 실패 시
/// 로컬은 건드리지 않고 예외를 던져 화면이 에러를 처리하게 한다). 로컬 저장
/// 모드에서는 그 서버 의존 기능들을 [_requireServerId]가 안내와 함께 막고,
/// [deleteBook]만 로컬 삭제로 대신한다.
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
    StorageModeStore? storageMode,
  }) : _storageMode = storageMode ?? storageModeStore;

  final BookRecordApi _api;
  final BookshelfRepository _bookshelfRepository;
  final StorageModeStore _storageMode;

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
  Future<BookItem?> updateRecord(int userBookId, RecordPatch patch) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final current = await _bookshelfRepository.getById(userBookId);
    if (current == null) return null;
    if (patch.isEmpty) return current;

    final merged = current.copyWithRecord(
      patch,
      updatedAt: DateTime.now().toUtc(),
    );

    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return null;
    }
    await _bookshelfRepository.applyLocalEdit(
      merged,
      changedFields: patch.changedFields,
    );

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
    String? coverImageUrl,
    File? thumbnailFile,
    bool removeThumbnail = false,
  }) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final current = await _requireLocal(userBookId);
    if (await _storageMode.isLocal()) {
      return _updateBookInfoLocally(
        current,
        title: title,
        author: author,
        publisher: publisher,
        totalPages: totalPages,
        categoryId: categoryId,
        coverImageUrl: coverImageUrl,
        thumbnailFile: thumbnailFile,
        removeThumbnail: removeThumbnail,
      );
    }
    final serverUserBookId = await _requireServerId(current);
    final data = await _api.patchBookInfo(
      userBookId: serverUserBookId,
      title: title,
      author: author,
      publisher: publisher,
      totalPages: totalPages,
      categoryId: categoryId,
      coverImageUrl: coverImageUrl,
      thumbnailFile: thumbnailFile,
      removeThumbnail: removeThumbnail,
    );
    return _persist(current, data, expectedGeneration);
  }

  /// ISBN 연결/재연결/연결 해제(`PATCH /api/me/books/:userBookId/link`).
  /// 연결·재연결이면 응답의 display 필드(제목/저자/출판사/총쪽수/표지/
  /// 카테고리)가 새로 연결한 책 기준으로 갱신돼 돌아오고, 해제([isbn13]이
  /// null)면 그 필드들은 기존값을 유지한 채 isbn13/bookId만 null이 된다
  /// (api-doc 기준) — 어느 쪽이든 응답을 그대로 로컬에 반영하면 된다.
  Future<BookItem> linkBook(
    int userBookId, {
    required String? isbn13,
    BookSearchItem? linkedBook,
  }) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final current = await _requireLocal(userBookId);
    if (await _storageMode.isLocal()) {
      return _linkBookLocally(current, isbn13: isbn13, linkedBook: linkedBook);
    }
    final serverUserBookId = await _requireServerId(current);
    final data = await _api.patchLink(
      userBookId: serverUserBookId,
      isbn13: isbn13,
    );
    return _persist(current, data, expectedGeneration);
  }

  /// 태그 추가. 서버는 태그 정보(id/name)만 반환하므로, 로컬 행에는 기존
  /// 태그 목록에 새 태그를 더해 반영한다.
  Future<BookItem> addTag(int userBookId, String name) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final current = await _requireLocal(userBookId);
    final serverUserBookId = await _requireServerId(current);
    final tag = await _api.postTag(userBookId: serverUserBookId, name: name);
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return current;
    }
    final latest = await _requireLocal(userBookId);
    final updated = latest.copyWithTags([
      ...latest.tags.where((existing) => existing.id != tag.id),
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
    final serverUserBookId = await _requireServerId(current);
    await _api.deleteTag(userBookId: serverUserBookId, tagId: tagId);
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return current;
    }
    final latest = await _requireLocal(userBookId);
    final updated = latest.copyWithTags(
      latest.tags.where((t) => t.id != tagId).toList(),
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
    final current = await _requireLocal(userBookId);
    // 로컬 저장 모드에서는 서버에 지울 기록이 없다 — 로컬에서만 지운다.
    if (await _storageMode.isLocal()) {
      await _bookshelfRepository.deleteLocal(userBookId);
      return;
    }
    final serverUserBookId = await _requireServerId(current);
    await _api.deleteUserBook(serverUserBookId);
    if (BookshelfDatabase.sessionGeneration == expectedGeneration) {
      await _bookshelfRepository.deleteLocal(userBookId);
    }
  }

  /// 로컬 저장 모드의 책 정보 수정. 서버 스냅샷이 아니라 사용자가 입력한
  /// 값이 그대로 원본이므로 로컬에 바로 반영한다. 새로 고른 표지 파일은
  /// [bookCoverImageStore]에 보관하고 그 상대 경로를 표지 값으로 쓴다
  /// (서버로 나가는 경로는 로컬 모드에서 모두 막혀 있다).
  Future<BookItem> _updateBookInfoLocally(
    BookItem current, {
    required String title,
    String? author,
    String? publisher,
    int? totalPages,
    int? categoryId,
    String? coverImageUrl,
    File? thumbnailFile,
    bool removeThumbnail = false,
  }) async {
    final previousCover = current.coverImageUrl;
    final String? nextCover;
    if (removeThumbnail) {
      nextCover = null;
    } else if (thumbnailFile != null) {
      nextCover = await _saveLocalCover(thumbnailFile);
    } else {
      nextCover = coverImageUrl ?? previousCover;
    }

    final updated = current.copyWithBookInfo(
      title: title,
      author: author,
      publisher: publisher,
      totalPages: totalPages,
      displayCategoryId: categoryId,
      // 카테고리 이름은 서버 응답으로만 오던 값이라, 선택이 바뀌면 이름은
      // 비워 두고 ID만 남긴다(화면은 ID로 마스터 목록에서 이름을 찾는다).
      category: categoryId == current.displayCategoryId
          ? current.category
          : null,
      coverImageUrl: nextCover,
      isbn13: current.isbn13,
      bookId: current.bookId,
      updatedAt: DateTime.now().toUtc(),
    );
    // 기록 필드(PATCH 대상)는 건드리지 않는 편집이라 추적 목록은 비운다.
    await _bookshelfRepository.applyLocalEdit(updated, changedFields: const {});
    // 더 이상 쓰지 않는 이전 로컬 표지 파일을 정리한다(서버 URL이면 무시).
    if (previousCover != nextCover) {
      await bookCoverImageStore.delete(previousCover, except: nextCover);
    }
    developer.log(
      '[책 정보 수정] userBookId=${current.userBookId} '
      'result=SUCCESS mode=local',
    );
    return updated;
  }

  /// 로컬 저장 모드의 ISBN 연결/해제. 연결할 책의 표시 정보([linkedBook])를
  /// 함께 받으면 제목·저자 등도 그 책 기준으로 갱신한다 — 서버 `bookId`는
  /// 알 수 없으므로 비운다(로컬에서는 쓰지 않는 값이다).
  Future<BookItem> _linkBookLocally(
    BookItem current, {
    required String? isbn13,
    BookSearchItem? linkedBook,
  }) async {
    final updated = current.copyWithBookInfo(
      title: linkedBook?.title ?? current.title,
      author: linkedBook?.author ?? current.author,
      publisher: linkedBook?.publisher ?? current.publisher,
      totalPages: current.totalPages,
      displayCategoryId: current.displayCategoryId,
      category: current.category,
      coverImageUrl: linkedBook?.coverUrl ?? current.coverImageUrl,
      isbn13: isbn13,
      bookId: null,
      updatedAt: DateTime.now().toUtc(),
    );
    await _bookshelfRepository.applyLocalEdit(updated, changedFields: const {});
    developer.log(
      '[ISBN 연결] userBookId=${current.userBookId} '
      'result=SUCCESS mode=local isbn13=${isbn13 ?? 'unlinked'}',
    );
    return updated;
  }

  Future<String?> _saveLocalCover(File file) async {
    try {
      return await bookCoverImageStore.saveSelected(file.path);
    } on FileSystemException catch (error) {
      throw ApiException(
        error.message.isEmpty ? '선택한 이미지를 찾을 수 없습니다.' : error.message,
      );
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

  /// 서버 호출이 필요한 기능(책 정보 수정·ISBN 연결·태그·삭제)의 공통
  /// 관문. 로컬 저장 모드에서는 서버 기록이 이미 정리돼 있어 어떤 요청도
  /// 의미가 없으므로, 404 대신 이유를 알려주고 막는다.
  Future<int> _requireServerId(BookItem item) async {
    if (await _storageMode.isLocal()) {
      throw const ApiException('로컬 저장 모드에서는 서버가 필요한 기능을 쓸 수 없습니다.');
    }
    if (item.serverId != null) return item.serverId!;
    await _bookshelfRepository.pushDirtyRecord(item.userBookId);
    final latest = await _bookshelfRepository.getById(item.userBookId);
    if (latest?.serverId != null) return latest!.serverId!;
    throw const ApiException('서버 연결 후 다시 시도해주세요.');
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
    final updated = BookItem.fromDetailJson(
      data,
      createdAt: current.createdAt,
      localUserBookId: current.userBookId,
      clientRequestId: current.clientRequestId,
      createThumbnailPath: current.createThumbnailPath,
    );
    if (BookshelfDatabase.sessionGeneration == expectedGeneration) {
      await _bookshelfRepository.upsertLocal(
        updated,
        syncedUpdatedAt: updated.updatedAt,
      );
    }
    return updated;
  }
}
