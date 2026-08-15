import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/models/book_tag.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../data/book_record_api.dart';
import '../data/book_record_repository.dart';

final bookRecordApiProvider = Provider<BookRecordApi>((ref) {
  return BookRecordApi(apiClient: ref.watch(apiClientProvider));
});

final bookRecordRepositoryProvider = Provider<BookRecordRepository>((ref) {
  return BookRecordRepository(
    api: ref.watch(bookRecordApiProvider),
    bookshelfRepository: ref.watch(bookshelfRepositoryProvider),
  );
});

/// 책 기록 상세 화면의 단일 책 상태. 로컬 DB 조회로 시작한다. [updateRecord]는
/// 로컬 우선(즉시 반영, 서버 반영은 뒤에서 조용히 재시도)이라 로딩 상태나
/// 에러를 노출하지 않고, 그 외 [updateBookInfo]/[addTag]/[removeTag]/
/// [deleteBook]은 서버 PATCH 성공 → 로컬 반영까지 끝난 뒤에만 상태를 갱신하며
/// 실패하면 이전 상태로 되돌리고 예외를 다시 던져 화면이 에러를 처리하게 한다.
///
/// `autoDispose` family: 화면을 벗어나 아무도 watch하지 않으면 즉시 폐기된다.
/// 그러지 않으면 한 번 열어본 책마다 컨트롤러가 앱 종료까지 살아남아, 다시
/// 들어갔을 때 그사이 다른 곳에서 바뀐 로컬 데이터 대신 오래된 캐시를 보여줄
/// 수 있고, 로그아웃 후에도 이전 계정의 책 데이터가 메모리에 남는다.
class BookRecordController
    extends AutoDisposeFamilyAsyncNotifier<BookItem?, int> {
  late BookRecordRepository _repository;

  /// [updateRecord] 연속 호출을 순서대로 실행시키는 체인. 각 호출은 이전
  /// 호출이 로컬 반영까지 끝난 뒤에만 시작된다.
  Future<void> _editChain = Future.value();

  @override
  FutureOr<BookItem?> build(int userBookId) async {
    // externalSyncVersionProvider만 watch한다(bookshelfSyncVersionProvider는
    // 이 컨트롤러 자신의 저장으로도 올라가므로 watch하면 저장할 때마다
    // build()가 다시 실행돼 로딩 오버레이가 불필요하게 깜빡인다). 이
    // 신호는 BookshelfSyncController의 실제 동기화가 로컬 DB를 바꿨을
    // 때만 올라가므로, 화면이 열려 있는 동안 다른 기기에서 이 책이
    // 바뀌어도 다시 읽어와 반영한다.
    ref.watch(externalSyncVersionProvider);
    _repository = ref.watch(bookRecordRepositoryProvider);
    return _repository.getLocal(userBookId);
  }

  /// 상태/진행률/평점 등 기본 기록 필드 수정(`PATCH /api/me/books/:userBookId`).
  /// 로컬에 즉시 반영하고 서버 반영은 [BookRecordRepository]가 뒤에서 조용히
  /// 시도한다 — 성공·실패와 무관하게 로딩 상태를 세우거나 예외를 던지지
  /// 않는다(실패하면 dirty로 남아 다음 동기화 때 일괄 재시도됨).
  ///
  /// 같은 책에 대한 연속 호출은 [_editChain]으로 순서를 강제한다 — 그러지
  /// 않으면 겹치는 호출의 로컬 read-modify-write(현재 값 조회 → 병합 →
  /// 저장)가 서로의 수정을 덮어쓸 수 있다.
  Future<void> updateRecord({
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
  }) {
    final chained = _editChain
        .then(
          (_) => _applyRecordEdit(
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
          ),
        )
        // 체인에 쌓인 Future가 에러로 완료되면 그 뒤에 이어붙는 .then들이
        // 전부 건너뛰어지며 에러가 그대로 전파된다 — 여기서 삼켜 체인이
        // 끊기지 않게 한다(어차피 이 메서드는 에러를 밖으로 보고하지 않음).
        .catchError((_, _) {});
    _editChain = chained;
    return chained;
  }

  Future<void> _applyRecordEdit({
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
    final updated = await _repository.updateRecord(
      arg,
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
    if (updated != null) {
      state = AsyncValue.data(updated);
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
    }
  }

  /// 시작일/완독일 "선택 해제". [updateRecord]와 달리 서버 PATCH 성공을
  /// 기다린 뒤에만 상태를 갱신한다([BookRecordRepository.clearReadingDate]
  /// 참고 — 로컬 우선 경로로는 "명시적으로 지움"이라는 의도가 유지되지
  /// 않는다).
  Future<void> clearReadingDate({required bool isStartedAt}) {
    return _mutate(
      () => _repository.clearReadingDate(arg, isStartedAt: isStartedAt),
    );
  }

  Future<BookItem> updateBookInfo({
    required String title,
    String? author,
    String? publisher,
    int? totalPages,
    int? categoryId,
    String? coverImageUrl,
    File? thumbnailFile,
    bool removeThumbnail = false,
  }) {
    return _mutate(
      () => _repository.updateBookInfo(
        arg,
        title: title,
        author: author,
        publisher: publisher,
        totalPages: totalPages,
        categoryId: categoryId,
        coverImageUrl: coverImageUrl,
        thumbnailFile: thumbnailFile,
        removeThumbnail: removeThumbnail,
      ),
    );
  }

  /// ISBN 연결/재연결/연결 해제. [isbn13]이 null이면 연결 해제다. 호출부
  /// (책 정보 수정 팝업)가 응답의 최신 display 필드로 입력창을 즉시 다시
  /// 채울 수 있도록 갱신된 [BookItem]을 그대로 반환한다.
  Future<BookItem> linkBook({required String? isbn13}) {
    return _mutate(() => _repository.linkBook(arg, isbn13: isbn13));
  }

  Future<BookItem> addTag(String name) =>
      _mutate(() => _repository.addTag(arg, name));

  /// 태그 삭제는 다른 필드 수정과 달리 로딩 상태를 거치지 않고 칩을 화면에서
  /// 즉시 지운 뒤(낙관적 삭제) 서버 응답을 기다린다 — 실패하면 [previous]로
  /// 되돌린다. `state.isLoading`을 세우지 않으므로 [_mutate]/[deleteBook]과의
  /// 동시성 가드는 [_isMutating] 플래그로 별도 관리한다.
  Future<void> removeTag(int tagId) async {
    if (_isMutating) {
      throw const ApiException('저장 중입니다. 잠시 후 다시 시도해주세요.');
    }
    final current = state.value;
    if (current == null) {
      throw const ApiException('존재하지 않거나 이미 삭제된 책입니다.');
    }
    final previous = state;
    _isMutating = true;
    state = AsyncValue.data(
      current.copyWithTags(
        current.tags.where((t) => t.id != tagId).toList(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    try {
      final updated = await _repository.removeTag(arg, tagId);
      state = AsyncValue.data(updated);
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
    } catch (e, st) {
      state = previous;
      Error.throwWithStackTrace(e, st);
    } finally {
      _isMutating = false;
    }
  }

  /// 성공하면 로컬 행도 함께 삭제되고 상태는 null이 된다. 화면은 성공 후
  /// 이전 화면으로 pop해야 한다(이 컨트롤러는 네비게이션을 하지 않는다).
  ///
  /// 다른 수정이 아직 진행 중이면(`state.isLoading` 또는 [_isMutating]) 예외를
  /// 던져 거부한다 — 그러지 않으면 PATCH/낙관적 삭제가 서버에 반영되기 전에
  /// DELETE가 로컬 행을 지우고, 뒤늦게 도착한 응답이 그 행을 다시 로컬에
  /// 살려낼 수 있다. 호출부는 전부 [ApiException]을 잡아 스낵바/인라인
  /// 에러로 보여주므로, 조용히 return하면 "저장된 것처럼 보이지만 실제로는
  /// 무시된" 상태가 된다 — 반드시 던져야 한다.
  Future<void> deleteBook() async {
    if (_isMutating) {
      throw const ApiException('저장 중입니다. 잠시 후 다시 시도해주세요.');
    }
    final previous = state;
    _isMutating = true;
    state = const AsyncValue<BookItem?>.loading().copyWithPrevious(state);
    try {
      await _repository.deleteBook(arg);
      state = const AsyncValue.data(null);
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
    } catch (e, st) {
      state = previous;
      Error.throwWithStackTrace(e, st);
    } finally {
      _isMutating = false;
    }
  }

  /// 같은 컨트롤러에서 수정이 겹치는 것을 막는다([deleteBook]과 동일한 이유
  /// — 진행 중인 PATCH와 또 다른 PATCH/DELETE가 응답 순서 역전으로 서로의
  /// 결과를 덮어쓰는 것을 방지). 조용히 무시하지 않고 던지는 이유도 동일하다.
  ///
  /// 가드는 [_isMutating]만 본다(`state.isLoading`은 보지 않는다) — 이
  /// 컨트롤러를 지켜보는 화면 없이(예: 완독 목록의 ISBN 일괄 연결 배너처럼
  /// `book_record_screen.dart`를 거치지 않는 경로) `ref.read`로 막 만들어진
  /// 인스턴스는 자기 초기 [build]가 아직 로컬 DB를 읽는 중이라
  /// `state.isLoading`이 true다. 그걸 "이미 저장 중"으로 오인하면, 이
  /// 컨트롤러의 첫 변이 요청부터 실제로는 아무 충돌도 없는데 "저장
  /// 중입니다"로 잘못 거부된다.
  Future<BookItem> _mutate(Future<BookItem> Function() action) async {
    if (_isMutating) {
      throw const ApiException('저장 중입니다. 잠시 후 다시 시도해주세요.');
    }
    final previous = state;
    _isMutating = true;
    state = const AsyncValue<BookItem?>.loading().copyWithPrevious(state);
    try {
      final updated = await action();
      state = AsyncValue.data(updated);
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
      return updated;
    } catch (e, st) {
      state = previous;
      Error.throwWithStackTrace(e, st);
    } finally {
      _isMutating = false;
    }
  }

  /// 진행 중인 변이(각 메서드가 값을 채워 넣음)를 표시하는 플래그. 초기
  /// [build]가 아직 안 끝나 `state.isLoading`이 true인 것과 "지금 이
  /// 컨트롤러가 저장 중"인 것을 구분하기 위해 별도로 관리한다(위 [_mutate]
  /// 문서 참고).
  bool _isMutating = false;
}

final bookRecordControllerProvider = AsyncNotifierProvider.autoDispose
    .family<BookRecordController, BookItem?, int>(BookRecordController.new);

/// 태그 입력창 자동완성 제안(내 전체 태그).
final tagSuggestionsProvider = FutureProvider.autoDispose<List<BookTag>>((ref) {
  return ref.watch(bookRecordRepositoryProvider).getTagSuggestions();
});

/// 전자책/오디오북 플랫폼 선택 목록(정적 데이터, 자주 바뀌지 않음).
final platformOptionsProvider =
    FutureProvider.autoDispose<Map<String, List<String>>>((ref) {
      return ref.watch(bookRecordRepositoryProvider).getPlatformOptions();
    });
