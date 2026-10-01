import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/ads/ad_slot_planner.dart';
import '../../../shared/ads/ads_enabled_provider.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_inline_banner_ad.dart';
import '../../../shared/widgets/community_content.dart';
import '../../book_detail/screens/book_detail_screen.dart';
import '../../bookshelf/screens/widgets/book_cover.dart';
import '../models/public_finished_book.dart';
import '../providers/public_bookshelf_providers.dart';
import '../widgets/user_report_flow.dart';

/// 다른 사용자의 공개 완독 책장 화면(`api-users-id-books-finished-get.md`).
///
/// 비로그인 상태로도 진입할 수 있고, 대상이 완독 목록을 비공개로 두었으면
/// 서버가 403을 내려준다 — 그 경우 일반 오류와 구분해 "비공개" 안내를
/// 보여준다.
class PublicFinishedBookshelfScreen extends ConsumerStatefulWidget {
  const PublicFinishedBookshelfScreen({
    super.key,
    required this.userId,
    this.nickname,
  });

  final int userId;

  /// 앱바 제목에 쓸 대상 사용자 닉네임(있으면 "OO님의 완독 책장").
  final String? nickname;

  @override
  ConsumerState<PublicFinishedBookshelfScreen> createState() =>
      _PublicFinishedBookshelfScreenState();
}

class _PublicFinishedBookshelfScreenState
    extends ConsumerState<PublicFinishedBookshelfScreen> {
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
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      ref
          .read(
            publicFinishedBooksControllerProvider(widget.userId).notifier,
          )
          .loadMore();
    }
  }

  void _openBook(PublicFinishedBook book) {
    final isbn13 = book.isbn13;
    if (isbn13 == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => BookDetailScreen(isbn: isbn13)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      publicFinishedBooksControllerProvider(widget.userId),
    );
    final adsEnabled = ref.watch(adsEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(
          widget.nickname == null ? '완독 책장' : '${widget.nickname}의 완독 책장',
        ),
        backgroundColor: AppColors.of(context).pageBackground,
        foregroundColor: AppColors.of(context).textStrong,
        elevation: 0,
        actions: [
          if (canReportUserNow(
            ProviderScope.containerOf(context, listen: false),
            widget.userId,
          ))
            IconButton(
              tooltip: '사용자 신고',
              icon: const Icon(PhosphorIconsRegular.siren),
              onPressed: () => reportUser(context, widget.userId),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          AsyncData(:final value) => _FinishedGrid(
            scrollController: _scrollController,
            items: value.items,
            isLoadingMore: value.isLoadingMore,
            onTapBook: _openBook,
            adsEnabled: adsEnabled,
          ),
          AsyncError(:final error) => _ErrorState(
            error: error,
            onRetry: () => ref.invalidate(
              publicFinishedBooksControllerProvider(widget.userId),
            ),
          ),
          _ => const CommunityContentLoadingState(),
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error is ApiException && (error as ApiException).statusCode == 403) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsRegular.lock,
                size: 36,
                color: AppColors.of(context).border,
              ),
              const SizedBox(height: 12),
              Text(
                '비공개 책장입니다',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.of(context).textBody,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                '이 사용자의 완독 책장이 공개되지 않았습니다',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.of(context).textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return CommunityContentErrorState(
      message: '불러오기에 실패했습니다',
      onRetry: onRetry,
    );
  }
}

class _FinishedGrid extends StatelessWidget {
  const _FinishedGrid({
    required this.scrollController,
    required this.items,
    required this.isLoadingMore,
    required this.onTapBook,
    required this.adsEnabled,
  });

  final ScrollController scrollController;
  final List<PublicFinishedBook> items;
  final bool isLoadingMore;
  final void Function(PublicFinishedBook book) onTapBook;
  final bool adsEnabled;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              '완독한 책이 없습니다',
              style: TextStyle(color: AppColors.of(context).textMuted),
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: _gridSliverWithAds(items, onTapBook: onTapBook),
        ),
        if (isLoadingMore)
          const SliverToBoxAdapter(child: CommunityContentPageLoader()),
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
        ),
      ],
    );
  }

  /// 책 개수가 아니라 그리드 열 개수(3열) 기준 8행마다 배너 광고를 한 행
  /// 전체 너비로 끼워 넣는다. 마지막 묶음 뒤에는 넣지 않는다. 더 불러오기로
  /// 항목이 뒤에 계속 늘어나는 화면이라 매번 전체 목록을 기준으로 다시
  /// 계산한다(월별 그룹처럼 별도 스크롤 인덱스가 없어 슬롯 높이를 따로
  /// 추적할 필요는 없다).
  Widget _gridSliverWithAds(
    List<PublicFinishedBook> items, {
    required void Function(PublicFinishedBook book) onTapBook,
  }) {
    const crossAxisCount = 3;
    const mainAxisSpacing = 16.0;
    // adsEnabled가 꺼져 있으면(추후 광고 제거 구매 등) 슬롯 자체를 만들지
    // 않는다 — 위젯만 숨기면 슬롯 사이 기본 행 간격만 빈 공간으로 남는다.
    final plan = adsEnabled
        ? planRowBasedAdSlots(
            segmentLengths: [items.length],
            crossAxisCount: crossAxisCount,
            rowsPerAd: 8,
          ).first
        : GridAdPlan(
            items.isEmpty ? const [] : [items.length],
            items.isEmpty ? const [] : [false],
          );

    var start = 0;
    final slivers = <Widget>[];
    for (var i = 0; i < plan.chunks.length; i++) {
      final take = plan.chunks[i];
      final chunkItems = items.sublist(start, start + take);
      final chunkStart = start;
      start += take;
      slivers.add(
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: mainAxisSpacing,
            childAspectRatio: 0.46,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _FinishedBookCard(
              book: chunkItems[index],
              onTap: () => onTapBook(chunkItems[index]),
            ),
            childCount: chunkItems.length,
          ),
        ),
      );
      if (plan.adAfterChunk[i]) {
        // 광고 로드 여부와 무관하게 원래 하나의 그리드였을 때의 행 간격을
        // 먼저 넣는다 — 로드 전/실패 시에도 앞뒤 행 사이 간격이 사라지지
        // 않도록(광고 위젯 자체는 그 위에 얹히는 추가 여백/콘텐츠만 담당).
        slivers.add(
          const SliverToBoxAdapter(child: SizedBox(height: mainAxisSpacing)),
        );
        slivers.add(
          SliverToBoxAdapter(
            child: AppInlineBannerAd(
              key: ValueKey('public-finished-ad-$chunkStart'),
              bottomSpacing: mainAxisSpacing,
            ),
          ),
        );
      }
    }
    return SliverMainAxisGroup(slivers: slivers);
  }
}

class _FinishedBookCard extends StatelessWidget {
  const _FinishedBookCard({required this.book, required this.onTap});

  final PublicFinishedBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: book.isbn13 == null ? null : onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              BookCover(
                imageUrl: book.coverImageUrl,
                title: book.title ?? '',
                useDiskCache: true,
              ),
              if (book.isMasterpiece)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                    child: const Icon(
                      PhosphorIconsFill.crown,
                      size: 20,
                      color: AppColors.highlightGold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            book.title ?? '',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.of(context).textStrong,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (book.myRating != null) _StarRow(rating: book.myRating!),
        ],
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final filled = rating.round().clamp(0, 5);
    return Row(
      children: List.generate(
        5,
        (i) => Icon(
          i < filled ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
          size: 12,
          color: i < filled
              ? AppColors.of(context).accentGraphic
              : AppColors.of(context).border,
        ),
      ),
    );
  }
}
