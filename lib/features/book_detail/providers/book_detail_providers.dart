import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/book_detail_api.dart';
import '../models/book_detail.dart';
import '../models/book_review.dart';

final bookDetailApiProvider = Provider<BookDetailApi>((ref) {
  return BookDetailApi(apiClient: ref.watch(apiClientProvider));
});

/// 책 상세 + 서재 포함 여부를 함께 담는 화면 상태.
class BookDetailData {
  const BookDetailData({
    required this.detail,
    required this.existsInShelf,
    this.userBookId,
  });

  final BookDetail detail;
  final bool existsInShelf;
  final int? userBookId;

  BookDetailData markAdded(int userBookId) {
    return BookDetailData(
      detail: detail,
      existsInShelf: true,
      userBookId: userBookId,
    );
  }
}

/// 책 상세 조회 + 서재 포함 여부 확인(`getBookshelfExists` 대응). [isbn]은
/// ISBN10/13 어느 쪽이든 받되, 이후 서재 담기/리뷰 API는 응답의 canonical
/// ISBN13([BookDetail.isbn])만 사용한다.
class BookDetailController
    extends AutoDisposeFamilyAsyncNotifier<BookDetailData, String> {
  late BookDetailApi _api;

  @override
  FutureOr<BookDetailData> build(String isbn) async {
    _api = ref.watch(bookDetailApiProvider);
    final detail = await _api.getBookDetail(isbn);
    final existsResult = await _api.checkExists(detail.isbn);
    return BookDetailData(
      detail: detail,
      existsInShelf: existsResult.exists,
      userBookId: existsResult.userBookId,
    );
  }

  /// 서재 담기 성공 후 버튼을 "이미 서재에 있음"으로 즉시 전환한다.
  void markAddedToShelf(int userBookId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(current.markAdded(userBookId));
  }
}

final bookDetailControllerProvider = AsyncNotifierProvider.autoDispose
    .family<BookDetailController, BookDetailData, String>(
      BookDetailController.new,
    );

/// 커뮤니티 리뷰 목록 상태(커서 기반 무한 스크롤).
class ReviewsState {
  const ReviewsState({
    required this.items,
    required this.nextCursor,
    required this.hasNext,
    this.isLoadingMore = false,
  });

  final List<BookReview> items;
  final int? nextCursor;
  final bool hasNext;
  final bool isLoadingMore;

  ReviewsState copyWith({
    List<BookReview>? items,
    int? nextCursor,
    bool? hasNext,
    bool? isLoadingMore,
  }) {
    return ReviewsState(
      items: items ?? this.items,
      nextCursor: nextCursor ?? this.nextCursor,
      hasNext: hasNext ?? this.hasNext,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// isbn13 기준 커뮤니티 리뷰 목록/작성/수정/삭제/좋아요.
class ReviewsController
    extends AutoDisposeFamilyAsyncNotifier<ReviewsState, String> {
  late BookDetailApi _api;

  /// `_reloadFirstPage()`(새로고침/작성 후 재조회)가 시작될 때마다 올라가는
  /// 세대값. `loadMore()`가 요청을 보낸 뒤 이 값이 바뀌었다면, 그 사이 첫
  /// 페이지가 통째로 교체된 것이므로 응답이 와도 병합하지 않고 버린다(오래된
  /// 커서 기준 페이지가 새로고침된 첫 페이지 뒤에 잘못 이어붙는 것을 방지).
  int _requestGeneration = 0;

  @override
  FutureOr<ReviewsState> build(String isbn13) async {
    _api = ref.watch(bookDetailApiProvider);
    final page = await _api.getReviews(isbn13: isbn13);
    return ReviewsState(
      items: page.items,
      nextCursor: page.nextCursor,
      hasNext: page.hasNext,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasNext || current.isLoadingMore) return;

    final generation = _requestGeneration;
    state = AsyncValue.data(current.copyWith(isLoadingMore: true));
    try {
      final page = await _api.getReviews(
        isbn13: arg,
        cursor: current.nextCursor,
      );
      if (generation != _requestGeneration) return;
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
      if (generation != _requestGeneration) return;
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data(latest.copyWith(isLoadingMore: false));
      }
    }
  }

  /// 리뷰 작성 후 목록을 처음부터 다시 불러온다(작성 응답에는 좋아요/작성자
  /// 정보가 없어 로컬 병합 대신 첫 페이지를 새로 조회하는 편이 안전하다).
  ///
  /// 등록(POST)과 새로고침(GET)의 성공 여부를 분리한다 — 등록은 됐는데
  /// 새로고침만 실패한 경우까지 전체를 실패로 던지면, 호출부가 입력값을
  /// 지우지 않고 오류로 안내해 사용자가 같은 내용을 다시 등록(중복 리뷰
  /// 생성)할 수 있다. 반환값은 새로고침 성공 여부로, 등록 자체는 여기까지
  /// 도달했다면 항상 성공한 것이다.
  Future<bool> submitReview({
    double? rating,
    required String content,
    required bool isSpoiler,
  }) async {
    await _api.postReview(
      isbn13: arg,
      rating: rating,
      content: content,
      isSpoiler: isSpoiler,
    );
    try {
      await _reloadFirstPage();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateReview(
    BookReview review, {
    double? rating,
    bool clearRating = false,
    required String content,
    required bool isSpoiler,
  }) async {
    await _api.patchReview(
      isbn13: arg,
      reviewId: review.id,
      rating: rating,
      clearRating: clearRating,
      content: content,
      isSpoiler: isSpoiler,
    );
    _updateItem(
      review.id,
      (r) => r.copyWith(
        rating: rating,
        clearRating: clearRating,
        content: content,
        isSpoiler: isSpoiler,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> deleteReview(int reviewId) async {
    await _api.deleteReview(isbn13: arg, reviewId: reviewId);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        items: current.items.where((r) => r.id != reviewId).toList(),
      ),
    );
  }

  /// 리뷰 신고. targetType은 항상 REVIEW로 고정한다.
  Future<void> reportReview(
    int reviewId, {
    required String reason,
    String? content,
  }) {
    return _api.postReport(
      targetType: 'REVIEW',
      targetId: reviewId,
      reason: reason,
      content: content,
    );
  }

  /// 좋아요 낙관적 토글. 실패해도 `conflict`/`notFound`면 이미 목표 상태와
  /// 같다고 보고 롤백하지 않는다(common-interactions.md).
  Future<void> toggleLike(BookReview review) async {
    final wasLiked = review.isLiked;
    _updateItem(
      review.id,
      (r) => r.copyWith(
        isLiked: !wasLiked,
        likeCount: wasLiked ? r.likeCount - 1 : r.likeCount + 1,
      ),
    );
    try {
      final likeCount = wasLiked
          ? await _api.deleteLike(targetType: 'REVIEW', targetId: review.id)
          : await _api.postLike(targetType: 'REVIEW', targetId: review.id);
      _updateItem(
        review.id,
        (r) => r.copyWith(isLiked: !wasLiked, likeCount: likeCount),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 409 || e.statusCode == 404) return;
      _updateItem(
        review.id,
        (r) => r.copyWith(isLiked: wasLiked, likeCount: review.likeCount),
      );
      rethrow;
    }
  }

  /// 당겨서 새로고침(전체 목록 화면). 실패해도 화면에 남아 있는 목록을
  /// 유지한다(다시 시도는 사용자가 결정, `DiscussionListController.refresh`와
  /// 동일한 방침).
  Future<void> refresh() async {
    try {
      await _reloadFirstPage();
    } catch (_) {
      // 화면에 남아 있는 목록을 유지한다.
    }
  }

  Future<void> _reloadFirstPage() async {
    _requestGeneration++;
    // 세대를 올리는 시점에 진행 중이던 loadMore()는 그 결과를 병합하지 않고
    // 버리게 되므로(위 generation 체크), 그 loadMore()가 남긴 isLoadingMore를
    // 여기서 미리 꺼 둔다 — 그렇지 않으면 이 재조회가 실패했을 때(catch에서
    // 기존 상태를 그대로 유지) 목록이 "더 불러오는 중" 상태로 영구히 멈춘다.
    final loadingMore = state.valueOrNull;
    if (loadingMore != null && loadingMore.isLoadingMore) {
      state = AsyncValue.data(loadingMore.copyWith(isLoadingMore: false));
    }
    final page = await _api.getReviews(isbn13: arg);
    state = AsyncValue.data(
      ReviewsState(
        items: page.items,
        nextCursor: page.nextCursor,
        hasNext: page.hasNext,
      ),
    );
  }

  void _updateItem(int id, BookReview Function(BookReview) update) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        items: [
          for (final item in current.items)
            if (item.id == id) update(item) else item,
        ],
      ),
    );
  }
}

final reviewsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ReviewsController, ReviewsState, String>(ReviewsController.new);
