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

/// 책 기록 상세 화면의 단일 책 상태. 로컬 DB 조회로 시작하고, 각 수정
/// 메서드는 서버 PATCH 성공 → 로컬 반영까지 끝난 뒤에만 상태를 갱신한다.
/// 실패하면 이전 상태로 되돌리고 예외를 다시 던져 화면이 에러를 처리하게 한다.
///
/// `autoDispose` family: 화면을 벗어나 아무도 watch하지 않으면 즉시 폐기된다.
/// 그러지 않으면 한 번 열어본 책마다 컨트롤러가 앱 종료까지 살아남아, 다시
/// 들어갔을 때 그사이 다른 곳에서 바뀐 로컬 데이터 대신 오래된 캐시를 보여줄
/// 수 있고, 로그아웃 후에도 이전 계정의 책 데이터가 메모리에 남는다.
class BookRecordController
    extends AutoDisposeFamilyAsyncNotifier<BookItem?, int> {
  late BookRecordRepository _repository;

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
    return _mutate(
      () => _repository.updateRecord(
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
      ),
    );
  }

  Future<void> updateBookInfo({
    required String title,
    String? author,
    String? publisher,
    int? totalPages,
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
        thumbnailFile: thumbnailFile,
        removeThumbnail: removeThumbnail,
      ),
    );
  }

  Future<void> addTag(String name) =>
      _mutate(() => _repository.addTag(arg, name));

  Future<void> removeTag(int tagId) =>
      _mutate(() => _repository.removeTag(arg, tagId));

  /// 성공하면 로컬 행도 함께 삭제되고 상태는 null이 된다. 화면은 성공 후
  /// 이전 화면으로 pop해야 한다(이 컨트롤러는 네비게이션을 하지 않는다).
  ///
  /// 다른 수정이 아직 진행 중이면(`state.isLoading`) 예외를 던져 거부한다
  /// — 그러지 않으면 PATCH가 서버에 반영되기 전에 DELETE가 로컬 행을
  /// 지우고, 뒤늦게 도착한 PATCH 응답이 그 행을 다시 로컬에 살려낼 수
  /// 있다. 호출부는 전부 [ApiException]을 잡아 스낵바/인라인 에러로
  /// 보여주므로, 조용히 return하면 "저장된 것처럼 보이지만 실제로는
  /// 무시된" 상태가 된다 — 반드시 던져야 한다.
  Future<void> deleteBook() async {
    if (state.isLoading) {
      throw const ApiException('저장 중입니다. 잠시 후 다시 시도해주세요.');
    }
    final previous = state;
    state = const AsyncValue<BookItem?>.loading().copyWithPrevious(state);
    try {
      await _repository.deleteBook(arg);
      state = const AsyncValue.data(null);
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
    } catch (e, st) {
      state = previous;
      Error.throwWithStackTrace(e, st);
    }
  }

  /// 같은 컨트롤러에서 수정이 겹치는 것을 막는다([deleteBook]과 동일한 이유
  /// — 진행 중인 PATCH와 또 다른 PATCH/DELETE가 응답 순서 역전으로 서로의
  /// 결과를 덮어쓰는 것을 방지). 조용히 무시하지 않고 던지는 이유도 동일하다.
  Future<void> _mutate(Future<BookItem> Function() action) async {
    if (state.isLoading) {
      throw const ApiException('저장 중입니다. 잠시 후 다시 시도해주세요.');
    }
    final previous = state;
    state = const AsyncValue<BookItem?>.loading().copyWithPrevious(state);
    try {
      final updated = await action();
      state = AsyncValue.data(updated);
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
    } catch (e, st) {
      state = previous;
      Error.throwWithStackTrace(e, st);
    }
  }
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
