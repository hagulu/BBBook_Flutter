import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/ads/ad_slot_planner.dart';
import '../../../shared/ads/ads_enabled_provider.dart';
import '../../../shared/widgets/app_banner_ad.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_inline_banner_ad.dart';
import '../../../shared/widgets/community_content.dart';
import '../../book_detail/screens/book_detail_screen.dart';
import '../../book_record/screens/book_record_screen.dart';
import '../../external_record_import/screens/external_import_guide_screen.dart';
import '../providers/book_search_providers.dart';
import 'barcode_scan_screen.dart';
import 'widgets/custom_book_dialog.dart';
import 'widgets/search_result_card.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 책 추가 화면(`/search` 대응, book-search.md). 하단 탭 셸의 "+" 버튼에서
/// 전체 화면으로 열리되, 아래에서 올라오는 전환과 X 닫기로 모달처럼 보인다.
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
      // 직접 등록도 검색 화면을 대체한다. 기록 상세에서 뒤로 가면 검색
      // 결과가 아니라 기존 책장으로 돌아간다.
      Navigator.of(context).pushReplacement(
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

  void _openExternalImport() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ExternalImportGuideScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookSearchControllerProvider);
    final adsEnabled = ref.watch(adsEnabledProvider);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fillViewportIfNeeded(),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.x),
          tooltip: '닫기',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const AppBarTitle('책 추가'),
        backgroundColor: AppColors.of(context).pageBackground,
        foregroundColor: AppColors.of(context).textStrong,
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
              // 입력 중에는 API를 호출하지 않는다. 키보드의 검색 버튼을
              // 눌렀을 때만 [_submit]이 첫 페이지를 조회한다.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: '책, 저자, ISBN으로 검색',
                prefixIcon: const Icon(
                  PhosphorIconsRegular.magnifyingGlass,
                  size: 18,
                ),
                // 실제 검색 요청이 진행 중일 때만 로딩을 표시한다.
                suffixIcon: state.isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _queryController.text.isEmpty
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
                adsEnabled: adsEnabled,
              ),
            )
          else ...[
            // 검색어가 없을 때만 노출되는 진입점이라 Expanded로 감싸 남는
            // 화면 아래쪽 전체를 차지하지 않고, 버튼 자체 높이만 차지하게 한다.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _EmptyQueryActions(
                onTapCustomBook: _openCustomBookDialog,
                onTapScan: _scanBarcode,
                onTapExternalImport: _openExternalImport,
              ),
            ),
            // 검색 전 하단 빈 공간을 광고로 채운다. 로드 전/실패 시에는
            // AppBannerAd 자체가 빈 크기로 접혀 빈 영역만 남지 않는다.
            const Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: AppBannerAd(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyQueryActions extends StatelessWidget {
  const _EmptyQueryActions({
    required this.onTapCustomBook,
    required this.onTapScan,
    required this.onTapExternalImport,
  });

  final VoidCallback onTapCustomBook;
  final VoidCallback onTapScan;

  /// null이면(계정 없음) 외부 기록 가져오기 버튼을 감춘다.
  final VoidCallback? onTapExternalImport;

  @override
  Widget build(BuildContext context) {
    final onTapExternalImport = this.onTapExternalImport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
        ),
        if (onTapExternalImport != null) ...[
          const SizedBox(height: 12),
          _CompactActionButton(
            icon: PhosphorIconsRegular.arrowSquareIn,
            label: '다른 서비스 기록 가져오기',
            caption: '북적북적 · 북모리',
            onTap: onTapExternalImport,
          ),
        ],
      ],
    );
  }
}

/// 아이콘과 라벨을 한 줄에 놓는 보조 등록 버튼(직접 등록·바코드).
/// 아이콘과 라벨을 한 줄에 놓는 보조 등록 버튼(직접 등록·바코드·외부 가져오기).
class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 라벨 뒤에 옅게 덧붙이는 보조 문구(예: 지원 서비스 이름).
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: colors.accentForeground, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: label,
                    children: [
                      if (caption != null)
                        TextSpan(
                          text: '  $caption',
                          style: TextStyle(
                            fontWeight: FontWeight.normal,
                            fontSize: 12,
                            color: colors.textMuted,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: colors.textStrong,
                  ),
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
    required this.adsEnabled,
  });

  final BookSearchState state;
  final ScrollController scrollController;
  final ValueChanged<String> onOpenDetail;
  final VoidCallback onRetry;
  final VoidCallback onRetryLoadMore;
  final bool adsEnabled;

  @override
  Widget build(BuildContext context) {
    // 이전 검색 결과가 아직 없을 때만 화면을 통째로 로딩으로 바꾼다. 이미
    // 보여줄 결과가 있으면(디바운스로 다음 검색이 진행 중인 경우 등) 목록을
    // 그대로 두고 옅게 표시만 해, 검색할 때마다 화면이 비었다 채워지는
    // 깜빡임을 없앤다.
    if (state.isLoading && state.items.isEmpty) {
      return const CommunityContentLoadingState();
    }

    final error = state.error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorMessage(error),
              style: TextStyle(color: AppColors.of(context).textMuted),
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
      return Center(
        child: Text(
          '검색 결과가 없습니다',
          style: TextStyle(color: AppColors.of(context).textMuted),
        ),
      );
    }

    final showLoadMoreRow = state.isLoadingMore || state.loadMoreError;
    // 검색 결과 목록에 10행마다 배너 광고를 끼워 넣는다. 더 불러오기로
    // 결과가 뒤에 계속 늘어나도([BookSearchState.items]가 페이지마다
    // append) 광고 위치는 항상 같은 지점(10번째, 20번째, ... 항목 뒤)을
    // 가리키므로 새로고침 없이도 안정적이다. adsEnabled가 꺼져 있으면
    // (추후 광고 제거 구매 등) 광고 항목 자체를 끼워 넣지 않는다.
    final entries = adsEnabled
        ? interleaveAdSlots(state.items, rowsPerAd: 10)
        : [for (final item in state.items) ItemAdSlotEntry(item)];
    final list = ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: entries.length + (showLoadMoreRow ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= entries.length) {
          return state.loadMoreError
              ? _LoadMoreError(onRetry: onRetryLoadMore)
              : const CommunityContentPageLoader();
        }
        final entry = entries[index];
        return switch (entry) {
          ItemAdSlotEntry(:final item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SearchResultCard(
              item: item,
              onTap: () => onOpenDetail(item.isbn),
            ),
          ),
          AdAdSlotEntry(:final afterCount) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppInlineBannerAd(key: ValueKey('search-ad-$afterCount')),
          ),
        };
      },
    );

    // 새 검색어로 다음 결과를 가져오는 동안(디바운스 이후) 기존 목록을
    // 옅게 보여주며 상단에 진행 표시만 얹는다 — 결과를 비웠다 다시 채우지
    // 않아 깜빡이지 않는다.
    if (!state.isLoading) return list;
    return Stack(
      children: [
        Opacity(opacity: 0.5, child: IgnorePointer(child: list)),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(
            minHeight: 2,
            color: AppColors.of(context).accentGraphic,
            backgroundColor: Colors.transparent,
          ),
        ),
      ],
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
          Flexible(
            child: Text(
              '검색 결과를 더 불러오지 못했습니다',
              style: TextStyle(
                color: AppColors.of(context).textMuted,
                fontSize: 12,
              ),
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
