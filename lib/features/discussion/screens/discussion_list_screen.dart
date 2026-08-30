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
        child: switch (state) {
          AsyncData(:final value) => _TopicList(
            scrollController: _scrollController,
            state: value,
            includeClosed: _includeClosed,
            onFilterChanged: (value) => setState(() => _includeClosed = value),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        tooltip: '토론 작성',
        shape: const CircleBorder(),
        backgroundColor: AppColors.accentFill,
        foregroundColor: AppColors.textStrong,
        child: const Icon(PhosphorIconsRegular.plus),
      ),
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList({
    required this.scrollController,
    required this.state,
    required this.includeClosed,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onOpen,
  });

  final ScrollController scrollController;
  final DiscussionListState<DiscussionTopic> state;
  final bool includeClosed;
  final ValueChanged<bool> onFilterChanged;
  final Future<void> Function() onRefresh;
  final void Function(int topicId) onOpen;

  @override
  Widget build(BuildContext context) {
    final filterRow = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilterChip(
            label: '열린 토론',
            isSelected: !includeClosed,
            onTap: () => onFilterChanged(false),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: '전체',
            isSelected: includeClosed,
            onTap: () => onFilterChanged(true),
          ),
        ],
      ),
    );

    if (state.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            filterRow,
            const SizedBox(height: 68),
            const Center(
              child: Text(
                '아직 등록된 토론이 없습니다.',
                style: TextStyle(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
        itemCount: 1 + state.items.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, index) =>
            index == 0 ? const SizedBox.shrink() : const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) return filterRow;
          final itemIndex = index - 1;
          if (itemIndex >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: CommunityContentPageLoader(),
            );
          }
          final topic = state.items[itemIndex];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DiscussionTopicCard(
              key: ValueKey(topic.id),
              topic: topic,
              onTap: () => onOpen(topic.id),
            ),
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
