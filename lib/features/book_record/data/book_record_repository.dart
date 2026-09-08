import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import '../../../core/network/api_exception.dart';
import '../../../core/network/patch_field.dart';
import '../../book_search/models/book_search_item.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../bookshelf/data/bookshelf_dao.dart'
    show bookInfoDirtyField, bookCoverDirtyField;
import '../../bookshelf/data/bookshelf_repository.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/models/book_tag.dart';
import '../../bookshelf/models/record_patch.dart';
import '../../bookshelf/services/book_cover_image_store.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import '../../tag/data/tag_repository.dart';
import 'book_record_api.dart';

/// 출처와 쪽수는 함께 로컬 저장하므로 서버 실패를 화면에 반환하지 않는다.
/// 기존 컨트롤러와의 호환을 위해 결과 형태를 유지한다.
typedef SourceTypeUpdateResult = ({BookItem item, ApiException? error});

/// 책 기록 상세 화면의 source of truth. 조회는 [BookshelfRepository]의 로컬
/// DB만 사용한다.
///
/// 기록·책 정보·표지 수정과 삭제는 로컬에 먼저 반영한다. 네트워크 실패는
/// dirty로 남겨 조용히 재시도한다. ISBN 연결만 서버 확인 후 반영하며,
/// 같은 책의 미전송 편집과 순서를 맞춘다. 저장 모드별 기존 태그/ISBN
/// 정책은 유지한다.
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
    required this._tagRepository,
    StorageModeStore? storageMode,
  }) : _storageMode = storageMode ?? storageModeStore;

  final BookRecordApi _api;
  final BookshelfRepository _bookshelfRepository;
  final TagRepository _tagRepository;
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
    int? statsTotalPages,
    int? displayTotalPages,
    int? categoryId,
    String? coverImageUrl,
    File? thumbnailFile,
    bool removeThumbnail = false,
  }) async {
    final generation = BookshelfDatabase.sessionGeneration;
    final current = await _requireLocal(userBookId);
    return _updateBookInfoLocally(
      current,
      generation: generation,
      title: title,
      author: author,
      publisher: publisher,
      statsTotalPages: statsTotalPages,
      displayTotalPages: displayTotalPages,
      categoryId: categoryId,
      coverImageUrl: coverImageUrl,
      thumbnailFile: thumbnailFile,
      removeThumbnail: removeThumbnail,
    );
  }

  /// 출처와 쪽수를 하나의 로컬 편집으로 저장한다. 재전송 시 기록 PATCH와
  /// book-info PATCH의 순서는 BookshelfRepository가 처리한다.
  Future<SourceTypeUpdateResult> updateSourceType(
    int userBookId, {
    required String sourceType,
    required PatchField<String>? platformName,
    PatchField<int>? displayTotalPages,
  }) async {
    final generation = BookshelfDatabase.sessionGeneration;
    final current = await _requireLocal(userBookId);
    final adjusted = current.normalizedCurrentPageForSourceChange(
      newSourceType: sourceType,
    );
    final patch = RecordPatch(
      currentPage: adjusted == current.currentPage ? null : adjusted,
      sourceType: PatchField.value(sourceType),
      platformName: platformName,
    );
    var updated = current.copyWithRecord(
      patch,
      updatedAt: DateTime.now().toUtc(),
    );
    if (displayTotalPages != null) {
      updated = updated.copyWithBookInfo(
        title: updated.title,
        author: updated.author,
        publisher: updated.publisher,
        statsTotalPages: updated.statsTotalPages,
        displayTotalPages: displayTotalPages.requestValue,
        displayCategoryId: updated.displayCategoryId,
        category: updated.category,
        coverImageUrl: updated.coverImageUrl,
        isbn13: updated.isbn13,
        bookId: updated.bookId,
        updatedAt: updated.updatedAt,
      );
    }
    _validateBookInfo(updated);
    _checkGeneration(generation);
    await _bookshelfRepository.applyLocalEdit(
      updated,
      changedFields: {
        ...patch.changedFields,
        if (displayTotalPages != null) bookInfoDirtyField,
      },
    );
    unawaited(_bookshelfRepository.pushDirtyRecord(userBookId));
    return (item: updated, error: null);
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
    await _api.prepareLink();
    _checkGeneration(expectedGeneration);
    await _bookshelfRepository.pushDirtyRecord(userBookId);
    _checkGeneration(expectedGeneration);
    return _bookshelfRepository.runSerializedForBook(userBookId, () async {
      final latest = await _requireLocal(userBookId);
      if (latest.serverId == null ||
          await _bookshelfRepository.hasPendingChanges(userBookId)) {
        throw const ApiException('서버에 기록을 동기화한 뒤 다시 연결해주세요.');
      }
      _checkGeneration(expectedGeneration);
      final data = await _api.patchLink(
        userBookId: latest.serverId!,
        isbn13: isbn13,
      );
      return _persist(latest, data, expectedGeneration);
    });
  }

  /// 태그 추가. 로컬 우선이다 — 즉시 로컬에 반영하고, 서버 push는
  /// [TagRepository]가 뒤에서 조용히 시도한다(실패해도 dirty로 남아 다음
  /// 동기화가 재시도한다). [BookItem.tags]는 저장된 값이 아니라 조회 시점에
  /// `tag`/`user_book_tag_map`을 조인한 값이므로([BookshelfDao._attachTags]),
  /// 로컬 반영 직후 다시 읽기만 하면 최신 태그가 그대로 보인다.
  Future<BookItem> addTag(int userBookId, String name) async {
    final current = await _requireLocal(userBookId);
    if (await _storageMode.isLocal()) {
      throw const ApiException('로컬 저장 모드에서는 서버가 필요한 기능을 쓸 수 없습니다.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const ApiException('태그명을 입력해주세요.');
    if (trimmed.length > 15) {
      throw const ApiException('태그명은 최대 15자까지 입력할 수 있습니다.');
    }
    if (current.tags.length >= 10) {
      throw const ApiException('태그는 책당 최대 10개까지 추가할 수 있습니다.');
    }
    await _tagRepository.addTag(userBookId: userBookId, name: trimmed);
    return _requireLocal(userBookId);
  }

  /// [tagId]는 서버 태그 ID가 아니라 로컬 태그 ID다(`BookItem.tags`에 담긴
  /// [BookTag.id] 그대로) — 오프라인에서 막 추가한 태그는 서버 ID가 아직
  /// 없을 수 있어, 화면은 항상 로컬 ID로 태그를 가리킨다.
  Future<BookItem> removeTag(int userBookId, int tagId) async {
    await _requireLocal(userBookId);
    if (await _storageMode.isLocal()) {
      throw const ApiException('로컬 저장 모드에서는 서버가 필요한 기능을 쓸 수 없습니다.');
    }
    await _tagRepository.removeTag(userBookId: userBookId, tagLocalId: tagId);
    return _requireLocal(userBookId);
  }

  Future<List<BookTag>> getTagSuggestions() async {
    final tags = await _tagRepository.getTagsByUsage();
    return tags.map((tag) => BookTag(id: tag.id, name: tag.name)).toList();
  }

  Future<Map<String, List<String>>> getPlatformOptions() =>
      _api.getPlatformOptions();

  Future<void> deleteBook(int userBookId) async {
    final generation = BookshelfDatabase.sessionGeneration;
    await _requireLocal(userBookId);
    final isLocal = await _storageMode.isLocal();
    _checkGeneration(generation);
    await _bookshelfRepository.deleteLocal(
      userBookId,
      queueServerDelete: !isLocal,
    );
  }

  /// 입력값과 선택한 표지 사본을 로컬 저장하고 업로드는 뒤에서 시도한다.
  Future<BookItem> _updateBookInfoLocally(
    BookItem current, {
    required int generation,
    required String title,
    String? author,
    String? publisher,
    int? statsTotalPages,
    int? displayTotalPages,
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
      statsTotalPages: statsTotalPages,
      displayTotalPages: displayTotalPages,
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
    try {
      _validateBookInfo(updated);
      _checkGeneration(generation);
    } catch (_) {
      if (thumbnailFile != null && nextCover != previousCover) {
        await bookCoverImageStore.delete(nextCover);
      }
      rethrow;
    }
    await _bookshelfRepository.applyLocalEdit(
      updated,
      changedFields: {
        bookInfoDirtyField,
        if (nextCover != previousCover) bookCoverDirtyField,
      },
    );
    unawaited(_bookshelfRepository.pushDirtyRecord(current.userBookId));
    // 더 이상 쓰지 않는 이전 로컬 표지 파일을 정리한다(서버 URL이면 무시).
    if (previousCover != nextCover) {
      await bookCoverImageStore.delete(previousCover, except: nextCover);
    }
    developer.log(
      '[책 정보 수정] userBookId=${current.userBookId} '
      'result=SUCCESS mode=local_first',
    );
    return updated;
  }

  void _validateBookInfo(BookItem item) {
    if (item.title.trim().isEmpty ||
        item.title.length > 255 ||
        (item.author?.length ?? 0) > 255 ||
        (item.publisher?.length ?? 0) > 255) {
      throw const ApiException('제목은 필수이며 제목·저자·출판사는 255자까지 입력할 수 있습니다.');
    }
    if ((item.statsTotalPages ?? 0) < 0 || (item.displayTotalPages ?? 0) < 0) {
      throw const ApiException('쪽수는 0 이상이어야 합니다.');
    }
    final total = item.effectiveTotalPages;
    if (!item.isAudioBook && total != null && item.currentPage > total) {
      throw const ApiException('총 쪽수는 현재 읽은 쪽수보다 작을 수 없습니다.');
    }
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
      statsTotalPages: current.statsTotalPages,
      displayTotalPages: current.displayTotalPages,
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

  void _checkGeneration(int generation) {
    if (BookshelfDatabase.sessionGeneration != generation) {
      throw const ApiException('로그인 상태가 변경되었습니다.');
    }
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
    _checkGeneration(expectedGeneration);
    await _bookshelfRepository.confirmLink(
      updated,
      capturedUpdatedAt: current.updatedAt,
    );
    return _requireLocal(current.userBookId);
  }
}
