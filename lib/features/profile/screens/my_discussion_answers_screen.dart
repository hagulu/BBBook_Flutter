import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_pagination.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/community_content.dart';
import '../../discussion/screens/discussion_detail_screen.dart';
import '../models/my_discussion_answer_summary.dart';
import '../providers/my_content_providers.dart';
import 'widgets/my_discussion_answer_card.dart';

/// "내가 작성한 토론 댓글" 목록(`my-content-screens.md` §5). 서버가 이
/// 엔드포인트만 페이지 번호로 응답해(`api-me-discussion-answers-get.md`),
/// 다른 3개 "내가 작성한 콘텐츠" 목록(커서 무한 스크롤)과 달리 숫자
/// 페이지네이션으로 보여준다.
class MyDiscussionAnswersScreen extends ConsumerWidget {
  const MyDiscussionAnswersScreen({super.key});

  Future<void> _openTopic(
    BuildContext context,
    WidgetRef ref,
    MyDiscussionAnswerSummary answer,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiscussionDetailScreen(
          topicId: answer.topicId,
          highlightAnswerId: answer.id,
        ),
      ),
    );
    // 상세에서 답변 수정·삭제가 있었을 수 있으니 돌아오면 보던 페이지를
    // 다시 조회한다(전체를 1페이지부터 다시 불러오면 위치를 잃는다).
    ref
        .read(myDiscussionAnswerPageControllerProvider.notifier)
        .reloadCurrentPage();
  }

  Future<void> _goToPage(BuildContext context, WidgetRef ref, int page) async {
    try {
      await ref
          .read(myDiscussionAnswerPageControllerProvider.notifier)
          .goToPage(page);
    } catch (_) {
      if (context.mounted) {
        AppSnackBar.error(context, '페이지를 불러오지 못했습니다');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myDiscussionAnswerPageControllerProvider);

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
          AsyncData(:final value) => _AnswerPage(
            state: value,
            onOpen: (answer) => _openTopic(context, ref, answer),
            onPageChanged: (page) => _goToPage(context, ref, page),
          ),
          AsyncError() => CommunityContentErrorState(
            message: '불러오기에 실패했습니다',
            onRetry: () =>
                ref.invalidate(myDiscussionAnswerPageControllerProvider),
          ),
          _ => const CommunityContentLoadingState(),
        },
      ),
    );
  }
}

class _AnswerPage extends StatelessWidget {
  const _AnswerPage({
    required this.state,
    required this.onOpen,
    required this.onPageChanged,
  });

  final MyDiscussionAnswerPageState state;
  final void Function(MyDiscussionAnswerSummary answer) onOpen;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty) {
      return const Center(
        child: Text(
          '작성한 토론 댓글이 없습니다',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    final list = ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: state.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final answer = state.items[index];
        return MyDiscussionAnswerCard(
          key: ValueKey(answer.id),
          answer: answer,
          onTap: () => onOpen(answer),
        );
      },
    );

    return SingleChildScrollView(
      child: Column(
        children: [
          AnimatedOpacity(
            opacity: state.isChangingPage ? 0.5 : 1,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(ignoring: state.isChangingPage, child: list),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
            child: AppPagination(
              currentPage: state.page,
              totalPages: state.totalPages,
              onPageChanged: onPageChanged,
            ),
          ),
        ],
      ),
    );
  }
}
