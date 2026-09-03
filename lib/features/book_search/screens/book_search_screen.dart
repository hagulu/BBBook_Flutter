import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/community_content.dart';
import '../../book_detail/screens/book_detail_screen.dart';
import '../../book_record/screens/book_record_screen.dart';
import '../providers/book_search_providers.dart';
import 'barcode_scan_screen.dart';
import 'widgets/custom_book_dialog.dart';
import 'widgets/search_result_card.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 책 검색 화면(`/search` 대응, book-search.md). 하단 탭 셸의 "+" 버튼으로
/// 진입하는 별도 화면이라 `Navigator.push`로 연다(BookRecordScreen과 동일 패턴).
class BookSearchScreen extends ConsumerStatefulWidget {
  const BookSearchScreen({super.key});

  @override
  ConsumerState<BookSearchScreen> createState() => _BookSearchScreenState();
}

class _BookSearchScreenState extends ConsumerState<BookSearchScreen> {
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  /// 목록 맨 끝에 실제로 닿았을 때만 다음 페이지를 가져온다(다른 화면의
  /// "여유 있게 미리" 로드하는 임계값과 달리, 검색 결과는 숫자 페이지네이션을
  /// 대체하는 것이라 스크롤이 끝에 닿기 전에는 반응하지 않는다).
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent) {
      ref.read(bookSearchControllerProvider.notifier).loadMore();
    }
  }

  /// 첫 페이지 결과가 화면을 다 채우지 못하면(넓은 화면·태블릿 등)
  /// `maxScrollExtent`가 0으로 고정돼 스크롤 자체가 발생하지 않아
  /// [_onScroll]이 다음 페이지를 요청할 기회가 없다. 매 빌드 직후 뷰포트가
  /// 아직 다 안 찼는지 확인해, 그럴 때만(그리고 더 가져올 페이지가 있을
  /// 때만) 이어서 요청한다. 응답으로 항목이 늘어나면 다음 빌드에서 다시
  /// 검사되므로, 뷰포트를 채우거나 마지막 페이지에 닿을 때까지 자연히
  /// 반복된다.
  void _fillViewportIfNeeded() {
    if (!mounted || !_scrollController.hasClients) return;
    final state = ref.read(bookSearchControllerProvider);
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    if (_scrollController.position.maxScrollExtent <= 0) {
      ref.read(bookSearchControllerProvider.notifier).loadMore();
    }
  }

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    ref
        .read(bookSearchControllerProvider.notifier)
        .search(_queryController.text);
  }

  void _clear() {
    _queryController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(bookSearchControllerProvider.notifier).clear();
    setState(() {});
  }

  Future<void> _openCustomBookDialog() async {
    final result = await showCustomBookDialog(context);
    if (result == null || !mounted) return;
    if (result.synced) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookRecordScreen(userBookId: result.userBookId),
        ),
      );
    }
  }

  void _openDetail(String isbn) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => BookDetailScreen(isbn: isbn)));
  }

  /// 바코드(ISBN) 스캔에 성공하면 검색 결과를 거치지 않고 바로 책 상세로 이동한다.
  Future<void> _scanBarcode() async {
    final isbn = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (isbn != null && mounted) _openDetail(isbn);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookSearchControllerProvider);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fillViewportIfNeeded(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('책 검색'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _queryController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: '책, 저자, ISBN으로 검색',
                prefixIcon: const Icon(
                  PhosphorIconsRegular.magnifyingGlass,
                  size: 18,
                ),
                suffixIcon: _queryController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(PhosphorIconsRegular.x, size: 18),
                        onPressed: _clear,
                      ),
              ),
            ),
          ),
          if (state.hasQuery)
            Expanded(
              child: _SearchResultsBody(
                state: state,
                scrollController: _scrollController,
                onOpenDetail: _openDetail,
                onRetry: _submit,
                onRetryLoadMore: () => ref
                    .read(bookSearchControllerProvider.notifier)
                    .retryLoadMore(),
              ),
            )
          else
            // 검색어가 없을 때만 노출되는 진입점이라 Expanded로 감싸 남는
            // 화면 아래쪽 전체를 차지하지 않고, 버튼 자체 높이만 차지하게 한다.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _EmptyQueryActions(
                onTapCustomBook: _openCustomBookDialog,
                onTapScan: _scanBarcode,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyQueryActions extends StatelessWidget {
  const _EmptyQueryActions({
    required this.onTapCustomBook,
    required this.onTapScan,
  });

  final VoidCallback onTapCustomBook;
  final VoidCallback onTapScan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CompactActionButton(
            icon: PhosphorIconsRegular.notePencil,
            label: '직접 등록',
            onTap: onTapCustomBook,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CompactActionButton(
            icon: PhosphorIconsRegular.barcode,
            label: '바코드로 등록',
            onTap: onTapScan,
          ),
        ),
      ],
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.accentSurface,
                child: Icon(icon, color: AppColors.accentForeground, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultsBody extends StatelessWidget {
  const _SearchResultsBody({
    required this.state,
    required this.scrollController,
    required this.onOpenDetail,
    required this.onRetry,
    required this.onRetryLoadMore,
  });

  final BookSearchState state;
  final ScrollController scrollController;
  final ValueChanged<String> onOpenDetail;
  final VoidCallback onRetry;
  final VoidCallback onRetryLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(
        child: Text('검색 중...', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    final error = state.error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorMessage(error),
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (error != BookSearchErrorType.auth) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ],
        ),
      );
    }

    if (state.items.isEmpty) {
      return const Center(
        child: Text(
          '검색 결과가 없습니다',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    final showLoadMoreRow = state.isLoadingMore || state.loadMoreError;
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: state.items.length + (showLoadMoreRow ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          return state.loadMoreError
              ? _LoadMoreError(onRetry: onRetryLoadMore)
              : const CommunityContentPageLoader();
        }
        final item = state.items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SearchResultCard(
            item: item,
            onTap: () => onOpenDetail(item.isbn),
          ),
        );
      },
    );
  }

  String _errorMessage(BookSearchErrorType error) => switch (error) {
    BookSearchErrorType.auth => '인증이 만료되었습니다.',
    BookSearchErrorType.server => '검색 중 문제가 발생했습니다.',
    BookSearchErrorType.network => '네트워크 연결을 확인해주세요.',
  };
}

class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Flexible(
            child: Text(
              '검색 결과를 더 불러오지 못했습니다',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('다시 시도', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
