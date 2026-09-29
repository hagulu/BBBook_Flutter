import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/ads/ad_slot_planner.dart';
import '../../../shared/ads/ads_enabled_provider.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_inline_banner_ad.dart';
import '../../../shared/widgets/community_content.dart';
import '../models/public_reflection.dart';
import '../providers/public_reflection_providers.dart';
import 'public_reflection_reader_screen.dart';
import 'widgets/public_reflection_card.dart';

/// ISBN13 한 권에 연결된 공개 독후감 목록.
class PublicReflectionListScreen extends ConsumerStatefulWidget {
  const PublicReflectionListScreen({
    super.key,
    required this.isbn13,
    required this.bookTitle,
  });

  final String isbn13;
  final String bookTitle;

  @override
  ConsumerState<PublicReflectionListScreen> createState() =>
      _PublicReflectionListScreenState();
}

class _PublicReflectionListScreenState
    extends ConsumerState<PublicReflectionListScreen> {
  final ScrollController _scrollController = ScrollController();

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
    if (position.pixels >= position.maxScrollExtent - 200) {
      ref
          .read(publicReflectionListControllerProvider(widget.isbn13).notifier)
          .loadMore();
    }
  }

  void _openReader(PublicReflectionSummary reflection) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PublicReflectionReaderScreen(
          isbn13: widget.isbn13,
          bookTitle: widget.bookTitle,
          reflectionId: reflection.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      publicReflectionListControllerProvider(widget.isbn13),
    );
    final adsEnabled = ref.watch(adsEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(widget.bookTitle, subtitle: '독후감'),
        backgroundColor: AppColors.of(context).pageBackground,
        foregroundColor: AppColors.of(context).textStrong,
        elevation: 0,
      ),
      body: switch (state) {
        AsyncData(:final value) => _ReflectionList(
          scrollController: _scrollController,
          state: value,
          onRefresh: () => ref
              .read(
                publicReflectionListControllerProvider(widget.isbn13).notifier,
              )
              .refresh(),
          onOpen: _openReader,
          adsEnabled: adsEnabled,
        ),
        AsyncError() => CommunityContentErrorState(
          message: '독후감을 불러오지 못했습니다.',
          onRetry: () => ref.invalidate(
            publicReflectionListControllerProvider(widget.isbn13),
          ),
        ),
        _ => const CommunityContentLoadingState(),
      },
    );
  }
}

class _ReflectionList extends StatelessWidget {
  const _ReflectionList({
    required this.scrollController,
    required this.state,
    required this.onRefresh,
    required this.onOpen,
    required this.adsEnabled,
  });

  final ScrollController scrollController;
  final PublicReflectionListState state;
  final Future<void> Function() onRefresh;
  final void Function(PublicReflectionSummary reflection) onOpen;
  final bool adsEnabled;

  @override
  Widget build(BuildContext context) {
    // 독후감 목록에 8행마다 배너 광고를 끼워 넣는다. adsEnabled가 꺼져
    // 있으면(추후 광고 제거 구매 등) 광고 항목 자체를 끼워 넣지 않는다.
    final entries = adsEnabled
        ? interleaveAdSlots(state.items, rowsPerAd: 8)
        : [for (final item in state.items) ItemAdSlotEntry(item)];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (state.items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 80),
                  child: Text(
                    '아직 공개된 독후감이 없습니다.',
                    style: TextStyle(color: AppColors.of(context).textMuted),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
              sliver: SliverList.separated(
                itemCount: entries.length + (state.isLoadingMore ? 1 : 0),
                separatorBuilder: (_, _) => const CommunityContentDivider(),
                itemBuilder: (context, index) {
                  if (index >= entries.length) {
                    return const CommunityContentPageLoader();
                  }
                  final entry = entries[index];
                  return switch (entry) {
                    ItemAdSlotEntry(:final item) => PublicReflectionCard(
                      key: ValueKey(item.id),
                      reflection: item,
                      onTap: () => onOpen(item),
                    ),
                    AdAdSlotEntry(:final afterCount) => AppInlineBannerAd(
                      key: ValueKey('reflection-ad-$afterCount'),
                    ),
                  };
                },
              ),
            ),
        ],
      ),
    );
  }
}
