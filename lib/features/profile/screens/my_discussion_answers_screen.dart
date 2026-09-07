import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/community_content.dart';
import '../../discussion/screens/discussion_detail_screen.dart';
import '../models/my_discussion_answer_summary.dart';
import '../providers/my_content_providers.dart';
import 'widgets/my_discussion_answer_card.dart';

/// "내가 작성한 토론 댓글" 목록(`my-content-screens.md` §5, cursor 기반
/// `api-me-discussion-answers-get.md`). 다른 3개 "내가 작성한 콘텐츠" 목록과
/// 동일하게 무한 스크롤로 보여준다.
class MyDiscussionAnswersScreen extends ConsumerStatefulWidget {
  const MyDiscussionAnswersScreen({super.key});

  @override
  ConsumerState<MyDiscussionAnswersScreen> createState() =>
      _MyDiscussionAnswersScreenState();
}

class _MyDiscussionAnswersScreenState
    extends ConsumerState<MyDiscussionAnswersScreen> {
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
      ref.read(myDiscussionAnswerListControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _openTopic(MyDiscussionAnswerSummary answer) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiscussionDetailScreen(
          topicId: answer.topicId,
          highlightAnswerId: answer.id,
        ),
      ),
    );
    // 상세에서 답변 수정·삭제가 있었을 수 있으니 돌아오면 목록을 다시 조회한다.
    if (mounted) ref.invalidate(myDiscussionAnswerListControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myDiscussionAnswerListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('내가 작성한 토론 댓글'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          AsyncData(:final value) => _AnswerList(
            scrollController: _scrollController,
            items: value.items,
            isLoadingMore: value.isLoadingMore,
            onOpen: _openTopic,
          ),
          AsyncError() => CommunityContentErrorState(
            message: '불러오기에 실패했습니다',
            onRetry: () =>
                ref.invalidate(myDiscussionAnswerListControllerProvider),
          ),
          _ => const CommunityContentLoadingState(),
        },
      ),
    );
  }
}

class _AnswerList extends StatelessWidget {
  const _AnswerList({
    required this.scrollController,
    required this.items,
    required this.isLoadingMore,
    required this.onOpen,
  });

  final ScrollController scrollController;
  final List<MyDiscussionAnswerSummary> items;
  final bool isLoadingMore;
  final void Function(MyDiscussionAnswerSummary answer) onOpen;

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
              '작성한 토론 댓글이 없습니다',
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
        final answer = items[index];
        return MyDiscussionAnswerCard(
          key: ValueKey(answer.id),
          answer: answer,
          onTap: () => onOpen(answer),
        );
      },
    );
  }
}
