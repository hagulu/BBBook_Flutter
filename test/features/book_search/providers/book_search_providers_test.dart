import 'package:bbbook/features/book_search/models/book_search_item.dart';
import 'package:bbbook/features/book_search/providers/book_search_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BookSearchPage pageOf(String query, int page, {int totalResults = 1}) {
    return BookSearchPage(
      items: [BookSearchItem(title: '$query $page', isbn: '$page')],
      totalResults: totalResults,
      page: page,
      size: 30,
    );
  }

  test('onQueryChanged는 debounce 시간 전에는 요청하지 않는다', () async {
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        bookSearchFetcherProvider.overrideWithValue(({
          required query,
          required page,
        }) async {
          calls++;
          return pageOf(query, page);
        }),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose 프로바이더가 구독자 없이 즉시 폐기되면 디바운스 타이머도
    // 함께 취소되므로, 실제 화면처럼 구독을 유지해둔다.
    addTearDown(
      container.listen(bookSearchControllerProvider, (_, _) {}).close,
    );

    final controller = container.read(bookSearchControllerProvider.notifier);
    controller.onQueryChanged('해리포터');

    expect(calls, 0);
  });

  test('debounce 시간이 지나면 마지막 입력으로 한 번만 검색한다', () async {
    final queries = <String>[];
    final container = ProviderContainer(
      overrides: [
        bookSearchFetcherProvider.overrideWithValue(({
          required query,
          required page,
        }) async {
          queries.add(query);
          return pageOf(query, page);
        }),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose 프로바이더가 구독자 없이 즉시 폐기되면 디바운스 타이머도
    // 함께 취소되므로, 실제 화면처럼 구독을 유지해둔다.
    addTearDown(
      container.listen(bookSearchControllerProvider, (_, _) {}).close,
    );

    final controller = container.read(bookSearchControllerProvider.notifier);
    // 빠르게 이어지는 입력 — 마지막 것만 검색되어야 한다.
    controller.onQueryChanged('해');
    controller.onQueryChanged('해리');
    controller.onQueryChanged('해리포터');

    await Future<void>.delayed(
      bookSearchDebounceDuration + const Duration(milliseconds: 100),
    );

    expect(queries, ['해리포터']);
    final state = container.read(bookSearchControllerProvider);
    expect(state.items.single.title, '해리포터 1');
    expect(state.isLoading, isFalse);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('입력이 비면 debounce 없이 즉시 결과를 비운다', () async {
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        bookSearchFetcherProvider.overrideWithValue(({
          required query,
          required page,
        }) async {
          calls++;
          return pageOf(query, page);
        }),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose 프로바이더가 구독자 없이 즉시 폐기되면 디바운스 타이머도
    // 함께 취소되므로, 실제 화면처럼 구독을 유지해둔다.
    addTearDown(
      container.listen(bookSearchControllerProvider, (_, _) {}).close,
    );

    final controller = container.read(bookSearchControllerProvider.notifier);
    controller.onQueryChanged('해리포터');
    controller.onQueryChanged('');

    await Future<void>.delayed(
      bookSearchDebounceDuration + const Duration(milliseconds: 100),
    );

    expect(calls, 0);
    final state = container.read(bookSearchControllerProvider);
    expect(state.items, isEmpty);
    expect(state.hasQuery, isFalse);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('먼저 시작한 느린 요청은 나중 요청의 결과를 덮어쓰지 않는다', () async {
    final container = ProviderContainer(
      overrides: [
        bookSearchFetcherProvider.overrideWithValue(({
          required query,
          required page,
        }) async {
          if (query == '느림') {
            await Future<void>.delayed(const Duration(milliseconds: 80));
          }
          return pageOf(query, page);
        }),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose 프로바이더가 구독자 없이 즉시 폐기되면 디바운스 타이머도
    // 함께 취소되므로, 실제 화면처럼 구독을 유지해둔다.
    addTearDown(
      container.listen(bookSearchControllerProvider, (_, _) {}).close,
    );

    final controller = container.read(bookSearchControllerProvider.notifier);
    final slow = controller.search('느림');
    final fast = controller.search('빠름');
    await Future.wait([slow, fast]);

    final state = container.read(bookSearchControllerProvider);
    expect(state.items.single.title, '빠름 1');
  });

  test('디바운스 대기 중 새 검색어를 입력하면 먼저 나간 요청의 늦은 응답을 무시한다', () async {
    final container = ProviderContainer(
      overrides: [
        bookSearchFetcherProvider.overrideWithValue(({
          required query,
          required page,
        }) async {
          if (query == 'A') {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          return pageOf(query, page);
        }),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(
      container.listen(bookSearchControllerProvider, (_, _) {}).close,
    );

    final controller = container.read(bookSearchControllerProvider.notifier);
    // A는 이미 네트워크 요청 중(디바운스를 거치지 않는 명시적 검색으로
    // 흉내낸다), B는 방금 입력해 아직 디바운스 대기 중이다.
    controller.search('A');
    controller.onQueryChanged('B');

    // A의 응답은 B의 디바운스가 끝나기 전에 도착한다.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    var state = container.read(bookSearchControllerProvider);
    expect(
      state.items,
      isEmpty,
      reason: '화면엔 B를 입력해 둔 상태이니 A의 늦은 응답이 반영되면 안 된다',
    );

    await Future<void>.delayed(
      bookSearchDebounceDuration + const Duration(milliseconds: 100),
    );
    state = container.read(bookSearchControllerProvider);
    expect(state.items.single.title, 'B 1');
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('loadMore는 스크롤이 실제로 멈춘 뒤에야 다음 페이지를 요청한다', () async {
    final calls = <int>[];
    final container = ProviderContainer(
      overrides: [
        bookSearchFetcherProvider.overrideWithValue(({
          required query,
          required page,
        }) async {
          calls.add(page);
          return BookSearchPage(
            items: [BookSearchItem(title: '책 $page', isbn: '$page')],
            totalResults: 3,
            page: page,
            size: 1,
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(
      container.listen(bookSearchControllerProvider, (_, _) {}).close,
    );

    final controller = container.read(bookSearchControllerProvider.notifier);
    await controller.search('책');
    calls.clear();

    // 관성 스크롤 중 바닥 판정 콜백이 여러 번 연달아 오는 상황을 흉내낸다.
    controller.loadMore();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    controller.loadMore();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    controller.loadMore();

    expect(calls, isEmpty, reason: '스크롤이 계속 이어지는 동안엔 아직 요청하지 않아야 한다');

    await Future<void>.delayed(
      bookSearchLoadMoreDebounceDuration + const Duration(milliseconds: 150),
    );

    expect(calls, [2], reason: '멈춘 뒤 한 번만, 마지막 시점의 다음 페이지를 요청해야 한다');
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('retryLoadMore는 지연 없이 바로 다음 페이지를 요청한다', () async {
    final calls = <int>[];
    final container = ProviderContainer(
      overrides: [
        bookSearchFetcherProvider.overrideWithValue(({
          required query,
          required page,
        }) async {
          calls.add(page);
          return BookSearchPage(
            items: [BookSearchItem(title: '책 $page', isbn: '$page')],
            totalResults: 3,
            page: page,
            size: 1,
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(
      container.listen(bookSearchControllerProvider, (_, _) {}).close,
    );

    final controller = container.read(bookSearchControllerProvider.notifier);
    await controller.search('책');
    calls.clear();

    await controller.retryLoadMore();

    expect(calls, [2]);
  });
}
