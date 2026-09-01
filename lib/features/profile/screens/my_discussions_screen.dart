import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/community_content.dart';
import '../../discussion/screens/discussion_detail_screen.dart';
import '../models/my_discussion_summary.dart';
import '../providers/my_content_providers.dart';
import 'widgets/my_discussion_card.dart';

/// "내가 작성한 토론" 목록(`my-content-screens.md` §4).
class MyDiscussionsScreen extends ConsumerStatefulWidget {
  const MyDiscussionsScreen({super.key});

  @override
  ConsumerState<MyDiscussionsScreen> createState() =>
      _MyDiscussionsScreenState();
}

class _MyDiscussionsScreenState extends ConsumerState<MyDiscussionsScreen> {
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
      ref.read(myDiscussionListControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _openDiscussion(MyDiscussionSummary discussion) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiscussionDetailScreen(topicId: discussion.id),
      ),
    );
    // 상세에서 수정·마감·삭제가 있었을 수 있으니 돌아오면 목록을 다시 조회한다.
    if (mounted) ref.invalidate(myDiscussionListControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myDiscussionListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('내가 작성한 토론'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          AsyncData(:final value) => _DiscussionList(
            scrollController: _scrollController,
            items: value.items,
            isLoadingMore: value.isLoadingMore,
            onOpen: _openDiscussion,
          ),
          AsyncError() => CommunityContentErrorState(
            message: '불러오기에 실패했습니다',
            onRetry: () => ref.invalidate(myDiscussionListControllerProvider),
          ),
          _ => const CommunityContentLoadingState(),
        },
      ),
    );
  }
}

class _DiscussionList extends StatelessWidget {
  const _DiscussionList({
    required this.scrollController,
    required this.items,
    required this.isLoadingMore,
    required this.onOpen,
  });

  final ScrollController scrollController;
  final List<MyDiscussionSummary> items;
  final bool isLoadingMore;
  final void Function(MyDiscussionSummary discussion) onOpen;

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
              '작성한 토론이 없습니다',
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
        final discussion = items[index];
        return MyDiscussionCard(
          key: ValueKey(discussion.id),
          discussion: discussion,
          onTap: discussion.isHidden ? null : () => onOpen(discussion),
        );
      },
    );
  }
}
