import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/community_content.dart';
import '../models/discussion_topic.dart';
import '../providers/discussion_providers.dart';
import 'discussion_detail_screen.dart';
import 'discussion_form_screen.dart';
import 'widgets/discussion_topic_card.dart';

/// 책 한 권의 주제 토론 목록(`/books/{isbn}/discussions` 대응).
///
/// 필터는 "열린 토론"(기본)/"전체" 두 가지이며, 전체를 고르면 `includeClosed`로
/// 다시 조회한다. 목록은 커서 기반 무한 스크롤이다.
class DiscussionListScreen extends ConsumerStatefulWidget {
  const DiscussionListScreen({
    super.key,
    required this.isbn13,
    required this.bookTitle,
  });

  final String isbn13;
  final String bookTitle;

  @override
  ConsumerState<DiscussionListScreen> createState() =>
      _DiscussionListScreenState();
}

class _DiscussionListScreenState extends ConsumerState<DiscussionListScreen> {
  final _scrollController = ScrollController();
  bool _includeClosed = false;

  DiscussionListArgs get _args =>
      (isbn13: widget.isbn13, includeClosed: _includeClosed);

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
      ref.read(discussionListControllerProvider(_args).notifier).loadMore();
    }
  }

  Future<void> _openForm() async {
    final createdId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => DiscussionFormScreen.create(isbn13: widget.isbn13),
      ),
    );
    if (!mounted) return;
    if (createdId != null) {
      await _openDetail(createdId);
    }
  }

  Future<void> _openDetail(int topicId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiscussionDetailScreen(topicId: topicId),
      ),
    );
    if (!mounted) return;
    // 상세에서 작성/수정/닫기/삭제가 일어났을 수 있어 목록을 최신화한다.
    await ref.read(discussionListControllerProvider(_args).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discussionListControllerProvider(_args));

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(widget.bookTitle, subtitle: '주제 토론'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommunityContentListHeader(
              title: '주제 토론',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FilterChip(
                    label: '열린 토론',
                    isSelected: !_includeClosed,
                    onTap: () => setState(() => _includeClosed = false),
                  ),
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: '전체',
                    isSelected: _includeClosed,
                    onTap: () => setState(() => _includeClosed = true),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (state) {
                AsyncData(:final value) => _TopicList(
                  scrollController: _scrollController,
                  state: value,
                  onRefresh: () => ref
                      .read(discussionListControllerProvider(_args).notifier)
                      .refresh(),
                  onOpen: _openDetail,
                ),
                AsyncError() => CommunityContentErrorState(
                  message: '토론을 불러오지 못했습니다.',
                  onRetry: () =>
                      ref.invalidate(discussionListControllerProvider(_args)),
                ),
                _ => const CommunityContentLoadingState(),
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        backgroundColor: AppColors.accentFill,
        foregroundColor: AppColors.textStrong,
        icon: const Icon(PhosphorIconsRegular.plus, size: 18),
        label: const Text(
          '토론 작성',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList({
    required this.scrollController,
    required this.state,
    required this.onRefresh,
    required this.onOpen,
  });

  final ScrollController scrollController;
  final DiscussionListState<DiscussionTopic> state;
  final Future<void> Function() onRefresh;
  final void Function(int topicId) onOpen;

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty) {
      return CommunityContentEmptyList(
        message: '아직 등록된 토론이 없습니다.',
        scrollController: scrollController,
        onRefresh: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const CommunityContentPageLoader();
          }
          final topic = state.items[index];
          return DiscussionTopicCard(
            key: ValueKey(topic.id),
            topic: topic,
            onTap: () => onOpen(topic.id),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentFill : AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? AppColors.textStrong : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
