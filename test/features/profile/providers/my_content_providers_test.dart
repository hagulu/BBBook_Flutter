import 'package:bbbook/features/profile/models/my_content_book.dart';
import 'package:bbbook/features/profile/models/my_discussion_answer_page.dart';
import 'package:bbbook/features/profile/models/my_discussion_answer_summary.dart';
import 'package:bbbook/features/profile/providers/my_content_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MyDiscussionAnswerSummary answer(int id) => MyDiscussionAnswerSummary(
    id: id,
    topicId: 100 + id,
    topicTitle: '토론 $id',
    isbn13: null,
    book: const MyContentBookRef(title: '책'),
    content: '댓글 $id',
    isHidden: false,
    createdAt: DateTime(2026, 1, 1),
  );

  MyDiscussionAnswerPage pageOf(int serverPage, int totalPages) {
    return MyDiscussionAnswerPage(
      items: [answer(serverPage)],
      page: serverPage,
      size: 20,
      totalElements: totalPages * 20,
      totalPages: totalPages,
    );
  }

  test('처음 build되면 0번(서버 기준) 페이지를 화면 1페이지로 보여준다', () async {
    final calls = <int>[];
    final container = ProviderContainer(
      overrides: [
        discussionAnswerFetcherProvider.overrideWithValue(({
          required page,
          required size,
        }) async {
          calls.add(page);
          return pageOf(page, 5);
        }),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(
      myDiscussionAnswerPageControllerProvider.future,
    );

    expect(calls, [0]);
    expect(state.page, 1);
    expect(state.totalPages, 5);
    expect(state.items.single.id, 0);
  });

  test('goToPage(3)은 서버에 0-based 페이지 2를 요청하고 상태를 갱신한다', () async {
    final calls = <int>[];
    final container = ProviderContainer(
      overrides: [
        discussionAnswerFetcherProvider.overrideWithValue(({
          required page,
          required size,
        }) async {
          calls.add(page);
          return pageOf(page, 5);
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(myDiscussionAnswerPageControllerProvider.future);
    final controller = container.read(
      myDiscussionAnswerPageControllerProvider.notifier,
    );
    await controller.goToPage(3);

    expect(calls, [0, 2]);
    final state = container
        .read(myDiscussionAnswerPageControllerProvider)
        .requireValue;
    expect(state.page, 3);
    expect(state.items.single.id, 2);
  });

  test('goToPage 실패 시 이전 페이지 상태를 유지하고 예외를 던진다', () async {
    var callCount = 0;
    final container = ProviderContainer(
      overrides: [
        discussionAnswerFetcherProvider.overrideWithValue(({
          required page,
          required size,
        }) async {
          callCount++;
          if (callCount == 1) return pageOf(page, 5);
          throw Exception('network error');
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(myDiscussionAnswerPageControllerProvider.future);
    final controller = container.read(
      myDiscussionAnswerPageControllerProvider.notifier,
    );

    await expectLater(controller.goToPage(2), throwsException);

    final state = container
        .read(myDiscussionAnswerPageControllerProvider)
        .requireValue;
    expect(state.page, 1, reason: '실패했으니 원래 보던 1페이지가 유지되어야 한다');
    expect(state.isChangingPage, isFalse);
  });

  test('reloadCurrentPage는 보던 페이지 그대로 다시 불러온다(1페이지부터 되돌아가지 않는다)', () async {
    final calls = <int>[];
    final container = ProviderContainer(
      overrides: [
        discussionAnswerFetcherProvider.overrideWithValue(({
          required page,
          required size,
        }) async {
          calls.add(page);
          return pageOf(page, 5);
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(myDiscussionAnswerPageControllerProvider.future);
    final controller = container.read(
      myDiscussionAnswerPageControllerProvider.notifier,
    );
    await controller.goToPage(4);
    calls.clear();

    await controller.reloadCurrentPage();

    expect(calls, [3], reason: '4페이지(화면)를 보고 있었으니 서버에는 3(0-based)을 다시 요청');
    final state = container
        .read(myDiscussionAnswerPageControllerProvider)
        .requireValue;
    expect(state.page, 4);
  });

  test(
    '마지막 페이지의 마지막 댓글을 지운 뒤 재조회하면 새로워진 마지막 페이지로 돌아간다',
    () async {
      final calls = <int>[];
      // 상세 화면에서 삭제가 일어나기 전엔 5페이지가 존재하고, 삭제 후엔
      // 서버 페이지 4(화면 5페이지)가 범위를 벗어나 빈 응답을 준다.
      var deleted = false;
      final container = ProviderContainer(
        overrides: [
          discussionAnswerFetcherProvider.overrideWithValue(({
            required page,
            required size,
          }) async {
            calls.add(page);
            if (deleted && page >= 4) {
              return const MyDiscussionAnswerPage(
                items: [],
                page: 4,
                size: 20,
                totalElements: 80,
                totalPages: 4,
              );
            }
            return pageOf(page, deleted ? 4 : 5);
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(myDiscussionAnswerPageControllerProvider.future);
      final controller = container.read(
        myDiscussionAnswerPageControllerProvider.notifier,
      );
      // 삭제 전 5페이지(서버 4)로 이동해 보고 있던 상태를 만든다.
      await controller.goToPage(5);
      // 상세에서 그 페이지의 마지막 댓글을 지웠다고 가정 — 전체가 4페이지로 준다.
      deleted = true;
      calls.clear();

      await controller.reloadCurrentPage();

      expect(
        calls,
        [4, 3],
        reason: '4는 범위를 벗어나 비어 있으니, 새로워진 마지막 페이지(3)를 한 번 더 조회해야 한다',
      );
      final state = container
          .read(myDiscussionAnswerPageControllerProvider)
          .requireValue;
      expect(state.page, 4, reason: '화면엔 새로워진 마지막 페이지(0-based 3 → 4)를 보여준다');
      expect(state.totalPages, 4);
      expect(state.items, isNotEmpty, reason: '더는 빈 목록으로 고립되면 안 된다');
    },
  );

  test('전부 삭제해 댓글이 하나도 없으면 빈 목록으로 남는다(추가 재조회 없음)', () async {
    final calls = <int>[];
    final container = ProviderContainer(
      overrides: [
        discussionAnswerFetcherProvider.overrideWithValue(({
          required page,
          required size,
        }) async {
          calls.add(page);
          return const MyDiscussionAnswerPage(
            items: [],
            page: 0,
            size: 20,
            totalElements: 0,
            totalPages: 0,
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(
      myDiscussionAnswerPageControllerProvider.future,
    );

    expect(calls, [0], reason: 'totalPages가 0이면 되돌아갈 유효한 페이지가 없으니 재조회하지 않는다');
    expect(state.items, isEmpty);
    expect(state.totalPages, 0);
  });
}
