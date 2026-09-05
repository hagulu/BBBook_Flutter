import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/book_search_api.dart';
import '../models/book_search_item.dart';

final bookSearchApiProvider = Provider<BookSearchApi>((ref) {
  return BookSearchApi(apiClient: ref.watch(apiClientProvider));
});

/// 검색 호출부를 함수 타입으로 감싸 provider 오버라이드만으로
/// [BookSearchController]의 요청 취소 로직을 테스트할 수 있게 한다
/// (Dio/ApiClient 목킹 없이 순수 로직만 검증).
typedef BookSearchFetcher =
    Future<BookSearchPage> Function({required String query, required int page});

final bookSearchFetcherProvider = Provider<BookSearchFetcher>((ref) {
  final api = ref.watch(bookSearchApiProvider);
  return api.searchBooks;
});

/// 스크롤이 바닥에 닿아도 이 시간만큼 멈칫한 뒤에만 다음 페이지를 가져온다.
/// 관성 스크롤 중에는 바닥 판정 콜백이 여러 번 연달아 오는데, 그때마다
/// 새로 미루기(디바운스)만 해도 스크롤이 실제로 멈출 때 한 번만 요청하게
/// 되어 과호출을 줄인다.
const bookSearchLoadMoreDebounceDuration = Duration(milliseconds: 500);

/// `book-search.md` 기준 화면 상태 3종(auth/server/network). auth는 이미
/// [ApiClient]가 401 → refresh 실패 시 로그아웃/온보딩 이동을 처리하므로,
/// 여기서는 재시도 버튼 없이 안내 문구만 보여준다.
enum BookSearchErrorType { auth, server, network }

class BookSearchState {
  const BookSearchState({
    this.query = '',
    this.page = 1,
    this.size = 30,
    this.items = const [],
    this.totalResults = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.loadMoreError = false,
    this.error,
  });

  final String query;
  final int page;
  final int size;
  final List<BookSearchItem> items;
  final int totalResults;
  final bool isLoading;
  final bool isLoadingMore;
  final bool loadMoreError;
  final BookSearchErrorType? error;

  bool get hasQuery => query.isNotEmpty;

  int get totalPages =>
      totalResults <= 0 ? 1 : (totalResults / size).ceil().clamp(1, 1 << 30);

  bool get hasMore => page < totalPages;

  BookSearchState copyWith({
    required String query,
    required int page,
    required int size,
    required List<BookSearchItem> items,
    required int totalResults,
    required bool isLoading,
    required bool isLoadingMore,
    required bool loadMoreError,
    BookSearchErrorType? error,
  }) {
    return BookSearchState(
      query: query,
      page: page,
      size: size,
      items: items,
      totalResults: totalResults,
      isLoading: isLoading,
      isLoadingMore: isLoadingMore,
      loadMoreError: loadMoreError,
      error: error,
    );
  }
}

/// 책 검색 화면 상태(검색어/페이지/결과). 웹은 URL 쿼리(`?q=&page=`)로
/// 상태를 유지하지만(book-search.md), 이 화면은 별도 딥링크 요구가 없어
/// 화면 상태로만 관리한다.
///
/// `autoDispose`로 둔다 — 이 화면(`BookSearchScreen`)만 구독하므로, 화면을
/// 완전히 빠져나가면(검색 결과를 거치지 않는 뒤로가기 포함) 상태가 사라지고
/// 다음에 새로 열 때는 빈 검색창과 함께 시작한다. 아니면 검색창 텍스트는
/// 화면을 새로 열 때마다 비워지는데(`_queryController`) provider 상태만
/// 남아, 빈 검색창인데 지난 검색 결과가 그대로 보이는 불일치가 생긴다.
class BookSearchController extends AutoDisposeNotifier<BookSearchState> {
  late BookSearchFetcher _fetchPage;

  /// 겹쳐 들어오는 요청 중 마지막 것만 반영한다(웹의 `AbortController` 취소와
  /// 동일 목적 — common-interactions.md).
  int _requestId = 0;

  Timer? _loadMoreDebounceTimer;

  @override
  BookSearchState build() {
    _fetchPage = ref.watch(bookSearchFetcherProvider);
    ref.onDispose(() {
      _loadMoreDebounceTimer?.cancel();
    });
    return const BookSearchState();
  }

  /// 검색창의 완료(엔터/검색 버튼) 액션 등 즉시 검색이 필요할 때 호출한다.
  Future<void> search(String query) {
    _loadMoreDebounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clear();
      return Future.value();
    }
    final requestId = ++_requestId;
    return _fetch(query: trimmed, page: 1, requestId: requestId);
  }

  /// 목록 스크롤이 끝에 닿을 때마다 호출한다(화면의 스크롤 리스너가 판단).
  /// 관성 스크롤 중엔 이 콜백이 연달아 오므로, 매번 새로 미뤄
  /// [bookSearchLoadMoreDebounceDuration] 동안 스크롤이 실제로 멈춰야만
  /// 다음 페이지를 요청한다 — 무지성으로 빠르게 내려도 API 호출은 그만큼
  /// 늘지 않고, 살짝 멈칫하는 느낌으로 다음 페이지가 이어진다.
  void loadMore() {
    if (!state.hasQuery ||
        state.isLoading ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }
    _loadMoreDebounceTimer?.cancel();
    final query = state.query;
    final page = state.page + 1;
    final requestId = ++_requestId;
    _loadMoreDebounceTimer = Timer(
      bookSearchLoadMoreDebounceDuration,
      () => _fetchMore(query: query, page: page, requestId: requestId),
    );
  }

  /// 목록 끝의 "다시 시도" 버튼: 명시적 액션이니 지연 없이 바로 요청한다.
  Future<void> retryLoadMore() {
    if (!state.hasQuery || state.isLoading || state.isLoadingMore) {
      return Future.value();
    }
    _loadMoreDebounceTimer?.cancel();
    final requestId = ++_requestId;
    return _fetchMore(
      query: state.query,
      page: state.page + 1,
      requestId: requestId,
    );
  }

  /// X 버튼: 검색어/결과를 모두 비운다(book-search.md).
  void clear() {
    _loadMoreDebounceTimer?.cancel();
    _requestId++;
    state = const BookSearchState();
  }

  Future<void> _fetch({
    required String query,
    required int page,
    required int requestId,
  }) async {
    if (requestId != _requestId) return;
    state = state.copyWith(
      query: query,
      page: page,
      size: state.size,
      items: state.items,
      totalResults: state.totalResults,
      isLoading: true,
      isLoadingMore: false,
      loadMoreError: false,
      error: null,
    );
    try {
      final result = await _fetchPage(query: query, page: page);
      if (requestId != _requestId) return;
      state = state.copyWith(
        query: query,
        page: result.page,
        size: result.size,
        items: result.items,
        totalResults: result.totalResults,
        isLoading: false,
        isLoadingMore: false,
        loadMoreError: false,
        error: null,
      );
    } on ApiException catch (e) {
      if (requestId != _requestId) return;
      state = state.copyWith(
        query: query,
        page: page,
        size: state.size,
        items: const [],
        totalResults: 0,
        isLoading: false,
        isLoadingMore: false,
        loadMoreError: false,
        error: _errorTypeOf(e),
      );
    }
  }

  /// 다음 페이지를 이어 붙인다. [_fetch]와 달리 실패해도 기존 목록은
  /// 유지하고 목록 끝의 재시도 UI만 노출한다(`loadMoreError`).
  Future<void> _fetchMore({
    required String query,
    required int page,
    required int requestId,
  }) async {
    if (requestId != _requestId) return;
    state = state.copyWith(
      query: query,
      page: state.page,
      size: state.size,
      items: state.items,
      totalResults: state.totalResults,
      isLoading: false,
      isLoadingMore: true,
      loadMoreError: false,
      error: null,
    );
    try {
      final result = await _fetchPage(query: query, page: page);
      if (requestId != _requestId) return;
      state = state.copyWith(
        query: query,
        page: result.page,
        size: result.size,
        items: [...state.items, ...result.items],
        totalResults: result.totalResults,
        isLoading: false,
        isLoadingMore: false,
        loadMoreError: false,
        error: null,
      );
    } on ApiException catch (_) {
      if (requestId != _requestId) return;
      state = state.copyWith(
        query: query,
        page: state.page,
        size: state.size,
        items: state.items,
        totalResults: state.totalResults,
        isLoading: false,
        isLoadingMore: false,
        loadMoreError: true,
        error: null,
      );
    }
  }

  BookSearchErrorType _errorTypeOf(ApiException e) {
    if (e.isAuthFailure) return BookSearchErrorType.auth;
    if (e.statusCode == null) return BookSearchErrorType.network;
    return BookSearchErrorType.server;
  }
}

final bookSearchControllerProvider =
    NotifierProvider.autoDispose<BookSearchController, BookSearchState>(
      BookSearchController.new,
    );
