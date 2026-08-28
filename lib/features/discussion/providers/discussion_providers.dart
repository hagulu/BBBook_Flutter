import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/discussion_api.dart';
import '../models/discussion_answer.dart';
import '../models/discussion_topic.dart';

/// 목록/답변 목록 공통 페이지 크기(웹과 동일).
const int _kPageSize = 20;

final discussionApiProvider = Provider<DiscussionApi>((ref) {
  return DiscussionApi(apiClient: ref.watch(apiClientProvider));
});

/// 토론 목록 조회 조건. 필터(열린 토론/전체)를 바꾸면 다른 provider 인스턴스가
/// 되어 서버에서 다시 조회한다.
typedef DiscussionListArgs = ({String isbn13, bool includeClosed});

/// 목록/답변 목록이 공유하는 커서 기반 페이지 상태.
class DiscussionListState<T> {
  const DiscussionListState({
    required this.items,
    required this.nextCursor,
    required this.hasNext,
    this.isLoadingMore = false,
  });

  final List<T> items;
  final int? nextCursor;
  final bool hasNext;
  final bool isLoadingMore;

  DiscussionListState<T> copyWith({
    List<T>? items,
    int? nextCursor,
    bool? hasNext,
    bool? isLoadingMore,
  }) {
    return DiscussionListState<T>(
      items: items ?? this.items,
      nextCursor: nextCursor ?? this.nextCursor,
      hasNext: hasNext ?? this.hasNext,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// 책 한 권의 토론 주제 목록(커서 기반 무한 스크롤).
class DiscussionListController
    extends
        AutoDisposeFamilyAsyncNotifier<
          DiscussionListState<DiscussionTopic>,
          DiscussionListArgs
        > {
  late DiscussionApi _api;

  @override
  FutureOr<DiscussionListState<DiscussionTopic>> build(
    DiscussionListArgs arg,
  ) async {
    _api = ref.watch(discussionApiProvider);
    final page = await _api.getTopics(
      isbn13: arg.isbn13,
      includeClosed: arg.includeClosed,
      size: _kPageSize,
    );
    return DiscussionListState(
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
      final page = await _api.getTopics(
        isbn13: arg.isbn13,
        includeClosed: arg.includeClosed,
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

  /// 상세에서 돌아왔을 때(작성/삭제/닫기 등)와 당겨서 새로고침에서 첫 페이지부터
  /// 다시 조회한다. 실패해도 이미 보고 있던 목록을 지우지 않는다.
  Future<void> refresh() async {
    try {
      final page = await _api.getTopics(
        isbn13: arg.isbn13,
        includeClosed: arg.includeClosed,
        size: _kPageSize,
      );
      state = AsyncValue.data(
        DiscussionListState(
          items: page.items,
          nextCursor: page.nextCursor,
          hasNext: page.hasNext,
        ),
      );
    } catch (_) {
      // 화면에 남아 있는 목록을 유지한다(다시 시도는 사용자가 결정).
    }
  }
}

final discussionListControllerProvider =
    AsyncNotifierProvider.autoDispose.family<
      DiscussionListController,
      DiscussionListState<DiscussionTopic>,
      DiscussionListArgs
    >(DiscussionListController.new);

/// 토론 주제 상세(선택지 결과 집계 포함) + 주제 단위 액션.
class DiscussionDetailController
    extends AutoDisposeFamilyAsyncNotifier<DiscussionTopicDetail, int> {
  late DiscussionApi _api;

  @override
  FutureOr<DiscussionTopicDetail> build(int arg) async {
    _api = ref.watch(discussionApiProvider);
    return _api.getTopic(arg);
  }

  /// 답변 작성/수정/삭제 후 투표 결과를 최신화한다. 실패해도 화면에 남은
  /// 값을 유지하기 위해 예외를 삼킨다(답변 자체는 이미 반영된 상태).
  Future<void> reload() async {
    try {
      state = AsyncValue.data(await _api.getTopic(arg));
    } catch (_) {
      // 결과 집계만 갱신하지 못한 상태이므로 화면을 오류로 덮지 않는다.
    }
  }

  /// 닫기/재오픈/마감일 변경은 API 성공 시점에 바뀐 상태를 먼저 화면에
  /// 반영하고 나서 [reload]로 나머지(집계 등)를 맞춘다. 후속 조회만 실패해도
  /// 화면이 이전 상태(예: 아직 답변을 달 수 있는 열린 토론)에 머물지 않게
  /// 하기 위해서다. 닫기/재오픈 응답에는 책·작성자·집계가 없어 응답을 그대로
  /// 모델로 바꿔 쓸 수 없으므로, 확정된 필드만 반영한다.
  void _applyClosedState({
    required DateTime? closedAt,
    required DateTime? closesAt,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        closedAt: closedAt,
        closesAt: closesAt,
        isClosed:
            closedAt != null ||
            (closesAt != null && closesAt.isBefore(DateTime.now())),
      ),
    );
  }

  Future<void> close() async {
    await _api.closeTopic(arg);
    final current = state.valueOrNull;
    _applyClosedState(
      closedAt: DateTime.now().toUtc(),
      closesAt: current?.closesAt,
    );
    await reload();
  }

  Future<void> reopen() async {
    await _api.reopenTopic(arg);
    final current = state.valueOrNull;
    _applyClosedState(closedAt: null, closesAt: current?.closesAt);
    await reload();
  }

  Future<void> updateClosesAt(DateTime? closesAt) async {
    await _api.patchClosesAt(topicId: arg, closesAt: closesAt);
    final current = state.valueOrNull;
    _applyClosedState(closedAt: current?.closedAt, closesAt: closesAt);
    await reload();
  }

  Future<void> delete() => _api.deleteTopic(arg);

  Future<void> report({required String reason, String? content}) {
    return _api.postReport(
      targetType: 'DISCUSSION_TOPIC',
      targetId: arg,
      reason: reason,
      content: content,
    );
  }

  /// 공감 낙관적 토글. 실패해도 409(이미 공감)/404(이미 취소)면 목표 상태와
  /// 같다고 보고 롤백하지 않는다.
  Future<void> toggleLike() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final wasLiked = current.likedByMe;
    state = AsyncValue.data(
      current.copyWith(
        likedByMe: !wasLiked,
        likeCount: wasLiked ? current.likeCount - 1 : current.likeCount + 1,
      ),
    );
    try {
      final likeCount = wasLiked
          ? await _api.deleteLike(
              targetType: 'DISCUSSION_TOPIC',
              targetId: arg,
            )
          : await _api.postLike(targetType: 'DISCUSSION_TOPIC', targetId: arg);
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncValue.data(
        latest.copyWith(likedByMe: !wasLiked, likeCount: likeCount),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 409 || e.statusCode == 404) return;
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data(
          latest.copyWith(
            likedByMe: wasLiked,
            likeCount: current.likeCount,
          ),
        );
      }
      rethrow;
    }
  }
}

final discussionDetailControllerProvider =
    AsyncNotifierProvider.autoDispose.family<
      DiscussionDetailController,
      DiscussionTopicDetail,
      int
    >(DiscussionDetailController.new);

/// 토론 답변 목록(최신순, "더 보기" 커서 페이지네이션) + 답변 단위 액션.
class DiscussionAnswersController
    extends
        AutoDisposeFamilyAsyncNotifier<
          DiscussionListState<DiscussionAnswer>,
          int
        > {
  late DiscussionApi _api;

  @override
  FutureOr<DiscussionListState<DiscussionAnswer>> build(int arg) async {
    _api = ref.watch(discussionApiProvider);
    final page = await _api.getAnswers(topicId: arg, size: _kPageSize);
    return DiscussionListState(
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
      final page = await _api.getAnswers(
        topicId: arg,
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

  /// 답변 작성. 등록 후 첫 페이지를 다시 불러오되, 이미 "더 보기"로 읽어 둔
  /// 뒷페이지는 유지한다(웹과 동일 — 등록 때문에 목록이 접히지 않게 한다).
  ///
  /// 등록(POST)과 새로고침(GET)의 성공 여부를 분리한다(`ReviewsController`와
  /// 동일한 규약) — 등록은 됐는데 새로고침만 실패한 경우까지 예외로 던지면,
  /// 호출부가 작성 폼과 입력 내용을 남긴 채 오류만 안내해 사용자가 같은
  /// 답변을 한 번 더 등록(중복 생성)할 수 있다. 반환값은 새로고침 성공
  /// 여부이며, 여기까지 도달했다면 등록 자체는 항상 성공한 것이다.
  Future<bool> submit({
    required String content,
    required bool withOption,
    int? optionId,
  }) async {
    await _api.createAnswer(
      topicId: arg,
      content: content,
      withOption: withOption,
      optionId: optionId,
    );
    try {
      await _reloadFirstPageKeepingRest();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateAnswer({
    required int answerId,
    required String content,
  }) async {
    await _api.patchAnswer(topicId: arg, answerId: answerId, content: content);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        items: [
          for (final answer in current.items)
            if (answer.id == answerId)
              answer.copyWith(
                content: content,
                updatedAt: DateTime.now().toUtc(),
              )
            else
              answer,
        ],
      ),
    );
  }

  Future<void> deleteAnswer(int answerId) async {
    await _api.deleteAnswer(topicId: arg, answerId: answerId);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        items: current.items.where((a) => a.id != answerId).toList(),
      ),
    );
  }

  Future<void> report(
    int answerId, {
    required String reason,
    String? content,
  }) {
    return _api.postReport(
      targetType: 'DISCUSSION_ANSWER',
      targetId: answerId,
      reason: reason,
      content: content,
    );
  }

  /// 답변 공감 낙관적 토글([DiscussionDetailController.toggleLike]과 같은 규칙).
  Future<void> toggleLike(DiscussionAnswer answer) async {
    final wasLiked = answer.likedByMe;
    _updateItem(
      answer.id,
      (a) => a.copyWith(
        likedByMe: !wasLiked,
        likeCount: wasLiked ? a.likeCount - 1 : a.likeCount + 1,
      ),
    );
    try {
      final likeCount = wasLiked
          ? await _api.deleteLike(
              targetType: 'DISCUSSION_ANSWER',
              targetId: answer.id,
            )
          : await _api.postLike(
              targetType: 'DISCUSSION_ANSWER',
              targetId: answer.id,
            );
      _updateItem(
        answer.id,
        (a) => a.copyWith(likedByMe: !wasLiked, likeCount: likeCount),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 409 || e.statusCode == 404) return;
      _updateItem(
        answer.id,
        (a) => a.copyWith(likedByMe: wasLiked, likeCount: answer.likeCount),
      );
      rethrow;
    }
  }

  Future<void> _reloadFirstPageKeepingRest() async {
    final page = await _api.getAnswers(topicId: arg, size: _kPageSize);
    final current = state.valueOrNull;
    if (current == null) {
      state = AsyncValue.data(
        DiscussionListState(
          items: page.items,
          nextCursor: page.nextCursor,
          hasNext: page.hasNext,
        ),
      );
      return;
    }

    // 첫 페이지에 이미 포함된 항목은 빼고 기존 뒷페이지를 이어 붙인다.
    final firstPageIds = page.items.map((a) => a.id).toSet();
    final rest = current.items
        .where((a) => !firstPageIds.contains(a.id))
        .toList();
    // 뒷페이지를 유지하는 동안에도 "더 보기" 커서는 기존 값이 유효하다.
    // 첫 페이지만 다시 읽었으므로 뒤쪽 페이지 정보는 그대로 둔다.
    state = AsyncValue.data(
      DiscussionListState(
        items: [...page.items, ...rest],
        nextCursor: rest.isEmpty ? page.nextCursor : current.nextCursor,
        hasNext: rest.isEmpty ? page.hasNext : current.hasNext,
      ),
    );
  }

  void _updateItem(
    int id,
    DiscussionAnswer Function(DiscussionAnswer) update,
  ) {
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

final discussionAnswersControllerProvider =
    AsyncNotifierProvider.autoDispose.family<
      DiscussionAnswersController,
      DiscussionListState<DiscussionAnswer>,
      int
    >(DiscussionAnswersController.new);
