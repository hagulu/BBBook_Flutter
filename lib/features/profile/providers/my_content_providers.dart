import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/my_content_api.dart';
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

class MyDiscussionAnswerListController
    extends
        AutoDisposeAsyncNotifier<MyContentListState<MyDiscussionAnswerSummary>> {
  late MyContentApi _api;

  @override
  FutureOr<MyContentListState<MyDiscussionAnswerSummary>> build() async {
    _api = ref.watch(myContentApiProvider);
    final page = await _api.fetchDiscussionAnswers(size: _kPageSize);
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
      final page = await _api.fetchDiscussionAnswers(
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

final myDiscussionAnswerListControllerProvider = AsyncNotifierProvider
    .autoDispose<
      MyDiscussionAnswerListController,
      MyContentListState<MyDiscussionAnswerSummary>
    >(MyDiscussionAnswerListController.new);
