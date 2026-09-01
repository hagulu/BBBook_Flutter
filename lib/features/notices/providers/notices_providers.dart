import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/notices_api.dart';
import '../models/notice_detail.dart';
import '../models/notice_summary.dart';

/// 공지사항 목록 페이지 크기(`notices-screens.md` §1-2).
const int _kPageSize = 20;

final noticesApiProvider = Provider<NoticesApi>((ref) {
  return NoticesApi(apiClient: ref.watch(apiClientProvider));
});

/// 공지사항 목록 상태. 다음 페이지 실패를 별도 상태(`loadMoreError`)로
/// 구분해 목록 하단에서만 재시도할 수 있게 한다(`notices-screens.md` §1-3).
class NoticeListState {
  const NoticeListState({
    required this.items,
    required this.nextCursor,
    required this.hasNext,
    this.isLoadingMore = false,
    this.loadMoreError = false,
  });

  final List<NoticeSummary> items;
  final int? nextCursor;
  final bool hasNext;
  final bool isLoadingMore;
  final bool loadMoreError;

  NoticeListState copyWith({
    List<NoticeSummary>? items,
    int? nextCursor,
    bool? hasNext,
    bool? isLoadingMore,
    bool? loadMoreError,
  }) {
    return NoticeListState(
      items: items ?? this.items,
      nextCursor: nextCursor ?? this.nextCursor,
      hasNext: hasNext ?? this.hasNext,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: loadMoreError ?? this.loadMoreError,
    );
  }
}

class NoticeListController extends AutoDisposeAsyncNotifier<NoticeListState> {
  late NoticesApi _api;

  @override
  FutureOr<NoticeListState> build() async {
    _api = ref.watch(noticesApiProvider);
    final page = await _api.fetchNotices(size: _kPageSize);
    return NoticeListState(
      items: page.items,
      nextCursor: page.nextCursor,
      hasNext: page.hasNext,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null ||
        !current.hasNext ||
        current.isLoadingMore ||
        current.loadMoreError) {
      return;
    }

    state = AsyncValue.data(
      current.copyWith(isLoadingMore: true, loadMoreError: false),
    );
    try {
      final page = await _api.fetchNotices(
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
        state = AsyncValue.data(
          latest.copyWith(isLoadingMore: false, loadMoreError: true),
        );
      }
    }
  }

  /// 다음 페이지 실패 후 "다시 시도" 탭 시 같은 `nextCursor`로 재요청한다.
  Future<void> retryLoadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.loadMoreError) return;
    state = AsyncValue.data(current.copyWith(loadMoreError: false));
    await loadMore();
  }
}

final noticeListControllerProvider =
    AsyncNotifierProvider.autoDispose<NoticeListController, NoticeListState>(
      NoticeListController.new,
    );

/// 공지사항 상세 조회. 재시도는 `ref.invalidate`로 처리한다(`notices-screens.md`
/// §2-3의 `retryCount` 증가와 동등한 효과).
final noticeDetailProvider = FutureProvider.autoDispose
    .family<NoticeDetail, int>((ref, id) {
      final api = ref.watch(noticesApiProvider);
      return api.fetchNotice(id);
    });
