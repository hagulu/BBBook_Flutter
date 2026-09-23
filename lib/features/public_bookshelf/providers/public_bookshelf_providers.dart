import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/public_bookshelf_api.dart';
import '../models/public_finished_book.dart';

const int _kPageSize = 30;

final publicBookshelfApiProvider = Provider<PublicBookshelfApi>((ref) {
  return PublicBookshelfApi(apiClient: ref.watch(apiClientProvider));
});

/// 다른 사용자의 공개 완독 책장 커서 페이지 상태.
class PublicFinishedBooksState {
  const PublicFinishedBooksState({
    required this.items,
    required this.nextCursor,
    required this.nextCursorDate,
    required this.hasNext,
    this.isLoadingMore = false,
  });

  final List<PublicFinishedBook> items;
  final int? nextCursor;
  final DateTime? nextCursorDate;
  final bool hasNext;
  final bool isLoadingMore;

  PublicFinishedBooksState copyWith({
    List<PublicFinishedBook>? items,
    int? nextCursor,
    DateTime? nextCursorDate,
    bool? hasNext,
    bool? isLoadingMore,
  }) {
    return PublicFinishedBooksState(
      items: items ?? this.items,
      nextCursor: nextCursor ?? this.nextCursor,
      nextCursorDate: nextCursorDate ?? this.nextCursorDate,
      hasNext: hasNext ?? this.hasNext,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// [userId] 기준 완독 책장 커서 무한 스크롤 컨트롤러. 비공개(403)는
/// [AsyncError]로 그대로 올라오며, 화면은 `ApiException.statusCode == 403`
/// 여부로 일반 오류와 구분해 보여준다.
class PublicFinishedBooksController
    extends AutoDisposeFamilyAsyncNotifier<PublicFinishedBooksState, int> {
  late PublicBookshelfApi _api;

  @override
  FutureOr<PublicFinishedBooksState> build(int userId) async {
    _api = ref.watch(publicBookshelfApiProvider);
    final page = await _api.fetchFinishedBooks(userId: userId, size: _kPageSize);
    return PublicFinishedBooksState(
      items: page.items,
      nextCursor: page.nextCursor,
      nextCursorDate: page.nextCursorDate,
      hasNext: page.hasNext,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasNext || current.isLoadingMore) return;

    state = AsyncValue.data(current.copyWith(isLoadingMore: true));
    try {
      final page = await _api.fetchFinishedBooks(
        userId: arg,
        cursor: current.nextCursor,
        cursorDate: current.nextCursorDate,
        size: _kPageSize,
      );
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncValue.data(
        latest.copyWith(
          items: [...latest.items, ...page.items],
          nextCursor: page.nextCursor,
          nextCursorDate: page.nextCursorDate,
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

final publicFinishedBooksControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PublicFinishedBooksController, PublicFinishedBooksState, int>(
      PublicFinishedBooksController.new,
    );
