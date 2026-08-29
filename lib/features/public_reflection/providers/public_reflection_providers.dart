import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/public_reflection_api.dart';
import '../data/public_reflection_source.dart';
import '../models/public_reflection.dart';
import '../services/public_reflection_service.dart';

const _pageSize = 20;
const _unset = Object();

final publicReflectionApiProvider = Provider<PublicReflectionApi>((ref) {
  return PublicReflectionApi(apiClient: ref.watch(apiClientProvider));
});

final publicReflectionSourceProvider = Provider<PublicReflectionSource>((ref) {
  return ref.watch(publicReflectionApiProvider);
});

final publicReflectionServiceProvider = Provider<PublicReflectionService>((
  ref,
) {
  return PublicReflectionService(ref.watch(publicReflectionSourceProvider));
});

class PublicReflectionListState {
  const PublicReflectionListState({
    required this.items,
    required this.nextCursor,
    required this.hasNext,
    this.isLoadingMore = false,
  });

  final List<PublicReflectionSummary> items;
  final int? nextCursor;
  final bool hasNext;
  final bool isLoadingMore;

  PublicReflectionListState copyWith({
    List<PublicReflectionSummary>? items,
    Object? nextCursor = _unset,
    bool? hasNext,
    bool? isLoadingMore,
  }) {
    return PublicReflectionListState(
      items: items ?? this.items,
      nextCursor: nextCursor == _unset ? this.nextCursor : nextCursor as int?,
      hasNext: hasNext ?? this.hasNext,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// ISBN13 한 권의 공개 독후감 목록(커서 기반 무한 스크롤).
class PublicReflectionListController
    extends AutoDisposeFamilyAsyncNotifier<PublicReflectionListState, String> {
  late PublicReflectionService _service;

  @override
  FutureOr<PublicReflectionListState> build(String arg) async {
    _service = ref.watch(publicReflectionServiceProvider);
    final page = await _service.getPage(isbn13: arg, size: _pageSize);
    return PublicReflectionListState(
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
      final page = await _service.getPage(
        isbn13: arg,
        cursor: current.nextCursor,
        size: _pageSize,
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

  Future<void> refresh() async {
    try {
      final page = await _service.getPage(isbn13: arg, size: _pageSize);
      state = AsyncValue.data(
        PublicReflectionListState(
          items: page.items,
          nextCursor: page.nextCursor,
          hasNext: page.hasNext,
        ),
      );
    } catch (_) {
      // 새로고침 실패 시 이미 읽고 있던 공개 목록을 유지한다.
    }
  }
}

final publicReflectionListControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PublicReflectionListController, PublicReflectionListState, String>(
      PublicReflectionListController.new,
    );

typedef PublicReflectionDetailArgs = ({String isbn13, int reflectionId});

class PublicReflectionDetailController
    extends
        AutoDisposeFamilyAsyncNotifier<
          PublicReflectionDetail,
          PublicReflectionDetailArgs
        > {
  late PublicReflectionSource _source;
  bool _isTogglingLike = false;

  @override
  FutureOr<PublicReflectionDetail> build(PublicReflectionDetailArgs arg) {
    _source = ref.watch(publicReflectionSourceProvider);
    return ref
        .watch(publicReflectionServiceProvider)
        .getDetail(isbn13: arg.isbn13, reflectionId: arg.reflectionId);
  }

  /// 토론 공감과 같은 낙관적 토글. 409(이미 공감)와 404(이미 취소)는
  /// 요청한 목표 상태에 도달한 것으로 보고 화면 상태를 유지한다.
  Future<void> toggleLike() async {
    if (_isTogglingLike) return;
    final current = state.valueOrNull;
    if (current == null) return;

    _isTogglingLike = true;
    final wasLiked = current.likedByMe;
    state = AsyncValue.data(
      current.copyWith(
        likedByMe: !wasLiked,
        likeCount: wasLiked ? current.likeCount - 1 : current.likeCount + 1,
      ),
    );
    try {
      final likeCount = wasLiked
          ? await _source.deleteLike(arg.reflectionId)
          : await _source.postLike(arg.reflectionId);
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncValue.data(
        latest.copyWith(likedByMe: !wasLiked, likeCount: likeCount),
      );
    } on ApiException catch (error) {
      if (error.statusCode == 409 || error.statusCode == 404) return;
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data(
          latest.copyWith(likedByMe: wasLiked, likeCount: current.likeCount),
        );
      }
      rethrow;
    } finally {
      _isTogglingLike = false;
    }
  }
}

final publicReflectionDetailProvider = AsyncNotifierProvider.autoDispose
    .family<
      PublicReflectionDetailController,
      PublicReflectionDetail,
      PublicReflectionDetailArgs
    >(PublicReflectionDetailController.new);
