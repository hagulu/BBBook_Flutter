import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/community_content.dart';
import '../models/my_review_summary.dart';
import '../providers/my_content_providers.dart';
import 'widgets/my_review_card.dart';

/// "내가 작성한 독자평" 목록(`my-content-screens.md` §3).
///
/// 다른 3개 목록과 달리 항목을 탭해도 이동하는 상세 화면이 없다(정보 표시
/// 전용 목록).
class MyReviewsScreen extends ConsumerStatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  ConsumerState<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends ConsumerState<MyReviewsScreen> {
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
    if (position.pixels >= position.maxScrollExtent - 240) {
      ref.read(myReviewListControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myReviewListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('내가 작성한 독자평'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          AsyncData(:final value) => _ReviewList(
            scrollController: _scrollController,
            items: value.items,
            isLoadingMore: value.isLoadingMore,
          ),
          AsyncError() => CommunityContentErrorState(
            message: '불러오기에 실패했습니다',
            onRetry: () => ref.invalidate(myReviewListControllerProvider),
          ),
          _ => const CommunityContentLoadingState(),
        },
      ),
    );
  }
}

class _ReviewList extends StatelessWidget {
  const _ReviewList({
    required this.scrollController,
    required this.items,
    required this.isLoadingMore,
  });

  final ScrollController scrollController;
  final List<MyReviewSummary> items;
  final bool isLoadingMore;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(
            child: Text(
              '작성한 리뷰가 없습니다',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: items.length + (isLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const CommunityContentPageLoader();
        }
        final review = items[index];
        return MyReviewCard(key: ValueKey(review.id), review: review);
      },
    );
  }
}
