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

  test(
    'loadMore는 스크롤이 실제로 멈춘 뒤에야 다음 페이지를 요청한다',
    () async {
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
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

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
