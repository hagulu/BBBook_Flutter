import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/my_content_api.dart';
import '../models/my_discussion_answer_page.dart';
import '../models/my_discussion_answer_summary.dart';
import '../models/my_discussion_summary.dart';
import '../models/my_reflection_summary.dart';
import '../models/my_review_summary.dart';

/// "내가 작성한 콘텐츠" 4개 목록 공통 페이지 크기(`my-content-screens.md` §1-1).
const int _kPageSize = 20;

final myContentApiProvider = Provider<MyContentApi>((ref) {
  return MyContentApi(apiClient: ref.watch(apiClientProvider));
});

/// 4개 목록이 공유하는 커서 기반 페이지 상태.
class MyContentListState<T> {
  const MyContentListState({
    required this.items,
    required this.nextCursor,
    required this.hasNext,
    this.isLoadingMore = false,
  });

  final List<T> items;
  final int? nextCursor;
  final bool hasNext;
  final bool isLoadingMore;

  MyContentListState<T> copyWith({
    List<T>? items,
    int? nextCursor,
    bool? hasNext,
    bool? isLoadingMore,
  }) {
    return MyContentListState<T>(
      items: items ?? this.items,
      nextCursor: nextCursor ?? this.nextCursor,
      hasNext: hasNext ?? this.hasNext,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class MyReflectionListController
    extends AutoDisposeAsyncNotifier<MyContentListState<MyReflectionSummary>> {
  late MyContentApi _api;

  @override
  FutureOr<MyContentListState<MyReflectionSummary>> build() async {
    _api = ref.watch(myContentApiProvider);
    final page = await _api.fetchReflections(size: _kPageSize);
    return MyContentListState(
      items: page.items,
      nextCursor: page.nextCursor,
      hasNext: page.hasNext,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasNext || current.isLoadingMore) return;

    state = AsyncValue.data(current.copyWith(isLoadingMore: true));
    try {
      final page = await _api.fetchReflections(
        cursor: current.nextCursor,
        size: _kPageSize,
      );
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncValue.data(
        latest.copyWith(
          items: [...latest.items, ...page.items],
          nextCursor: page.nextCursor,
          hasNext: page.hasNext,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data(latest.copyWith(isLoadingMore: false));
      }
    }
  }
}

final myReflectionListControllerProvider = AsyncNotifierProvider.autoDispose<
  MyReflectionListController,
  MyContentListState<MyReflectionSummary>
>(MyReflectionListController.new);

class MyReviewListController
    extends AutoDisposeAsyncNotifier<MyContentListState<MyReviewSummary>> {
  late MyContentApi _api;

  @override
  FutureOr<MyContentListState<MyReviewSummary>> build() async {
    _api = ref.watch(myContentApiProvider);
    final page = await _api.fetchReviews(size: _kPageSize);
    return MyContentListState(
      items: page.items,
      nextCursor: page.nextCursor,
      hasNext: page.hasNext,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasNext || current.isLoadingMore) return;

    state = AsyncValue.data(current.copyWith(isLoadingMore: true));
    try {
      final page = await _api.fetchReviews(
        cursor: current.nextCursor,
        size: _kPageSize,
      );
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncValue.data(
        latest.copyWith(
          items: [...latest.items, ...page.items],
          nextCursor: page.nextCursor,
          hasNext: page.hasNext,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data(latest.copyWith(isLoadingMore: false));
      }
    }
  }
}

final myReviewListControllerProvider = AsyncNotifierProvider.autoDispose<
  MyReviewListController,
  MyContentListState<MyReviewSummary>
>(MyReviewListController.new);

class MyDiscussionListController
    extends AutoDisposeAsyncNotifier<MyContentListState<MyDiscussionSummary>> {
  late MyContentApi _api;

  @override
  FutureOr<MyContentListState<MyDiscussionSummary>> build() async {
    _api = ref.watch(myContentApiProvider);
    final page = await _api.fetchDiscussions(size: _kPageSize);
    return MyContentListState(
      items: page.items,
      nextCursor: page.nextCursor,
      hasNext: page.hasNext,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasNext || current.isLoadingMore) return;

    state = AsyncValue.data(current.copyWith(isLoadingMore: true));
    try {
      final page = await _api.fetchDiscussions(
        cursor: current.nextCursor,
        size: _kPageSize,
      );
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncValue.data(
        latest.copyWith(
          items: [...latest.items, ...page.items],
          nextCursor: page.nextCursor,
          hasNext: page.hasNext,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data(latest.copyWith(isLoadingMore: false));
      }
    }
  }
}

final myDiscussionListControllerProvider = AsyncNotifierProvider.autoDispose<
  MyDiscussionListController,
  MyContentListState<MyDiscussionSummary>
>(MyDiscussionListController.new);

/// 서버 API 호출부를 함수 타입으로 감싸 provider 오버라이드만으로
/// [MyDiscussionAnswerPageController]를 테스트할 수 있게 한다(Dio/ApiClient
/// 목킹 없이 순수 로직만 검증).
typedef DiscussionAnswerFetcher =
    Future<MyDiscussionAnswerPage> Function({
      required int page,
      required int size,
    });

final discussionAnswerFetcherProvider = Provider<DiscussionAnswerFetcher>((
  ref,
) {
  final api = ref.watch(myContentApiProvider);
  return api.fetchDiscussionAnswers;
});

/// "내가 작성한 토론 댓글" 목록 상태. 다른 3개와 달리 서버가 페이지 번호
/// 기반(`page`/`totalPages`)으로 응답해(`api-me-discussion-answers-get.md`),
/// 커서 무한 스크롤 대신 숫자 페이지네이션으로 보여준다.
///
/// [page]는 화면에 노출하는 1부터 시작하는 페이지 번호다(서버는 0부터 시작).
class MyDiscussionAnswerPageState {
  const MyDiscussionAnswerPageState({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalElements,
    this.isChangingPage = false,
  });

  final List<MyDiscussionAnswerSummary> items;
  final int page;
  final int totalPages;
  final int totalElements;
  final bool isChangingPage;

  MyDiscussionAnswerPageState copyWith({
    List<MyDiscussionAnswerSummary>? items,
    int? page,
    int? totalPages,
    int? totalElements,
    bool? isChangingPage,
  }) {
    return MyDiscussionAnswerPageState(
      items: items ?? this.items,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      totalElements: totalElements ?? this.totalElements,
      isChangingPage: isChangingPage ?? this.isChangingPage,
    );
  }
}

class MyDiscussionAnswerPageController
    extends AutoDisposeAsyncNotifier<MyDiscussionAnswerPageState> {
  late DiscussionAnswerFetcher _fetch;

  @override
  FutureOr<MyDiscussionAnswerPageState> build() async {
    _fetch = ref.watch(discussionAnswerFetcherProvider);
    return _loadPage(0);
  }

  /// [uiPage]는 1부터 시작하는 화면 페이지 번호.
  Future<void> goToPage(int uiPage) async {
    final current = state.valueOrNull;
    if (current == null || current.isChangingPage || uiPage == current.page) {
      return;
    }
    state = AsyncValue.data(current.copyWith(isChangingPage: true));
    try {
      final next = await _loadPage(uiPage - 1);
      state = AsyncValue.data(next);
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data(latest.copyWith(isChangingPage: false));
      }
      rethrow;
    }
  }

  /// 댓글 수정·삭제 후 상세에서 돌아왔을 때, 보던 페이지 그대로 다시
  /// 불러온다(전체를 1페이지부터 다시 불러오면 위치를 잃는다).
  Future<void> reloadCurrentPage() async {
    final current = state.valueOrNull;
    final serverPage = current == null ? 0 : current.page - 1;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadPage(serverPage));
  }

  Future<MyDiscussionAnswerPageState> _loadPage(int serverPage) async {
    var result = await _fetch(page: serverPage, size: _kPageSize);
    if (result.items.isEmpty &&
        result.totalPages > 0 &&
        result.page >= result.totalPages) {
      // 상세에서 어떤 페이지의 마지막 댓글을 지우면 전체 페이지 수가 줄어
      // 방금 요청한 페이지가 범위를 벗어날 수 있다. 이 경우를 그냥 "댓글
      // 없음"으로 보여주면 유효한 이전 페이지로 돌아갈 방법이 없어지니,
      // 새로워진 마지막 페이지로 한 번 더 조회한다.
      result = await _fetch(page: result.totalPages - 1, size: _kPageSize);
    }
    return MyDiscussionAnswerPageState(
      items: result.items,
      page: result.page + 1,
      totalPages: result.totalPages,
      totalElements: result.totalElements,
    );
  }
}

final myDiscussionAnswerPageControllerProvider = AsyncNotifierProvider
    .autoDispose<
      MyDiscussionAnswerPageController,
      MyDiscussionAnswerPageState
    >(MyDiscussionAnswerPageController.new);
