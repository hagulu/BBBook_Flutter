import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(widget.bookTitle, subtitle: '공개 독후감'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CommunityContentListHeader(title: '공개 독후감'),
            Expanded(
              child: switch (state) {
                AsyncData(:final value) => _ReflectionList(
                  scrollController: _scrollController,
                  state: value,
                  onRefresh: () => ref
                      .read(
                        publicReflectionListControllerProvider(
                          widget.isbn13,
                        ).notifier,
                      )
                      .refresh(),
                  onOpen: _openReader,
                ),
                AsyncError() => CommunityContentErrorState(
                  message: '독후감을 불러오지 못했습니다.',
                  onRetry: () => ref.invalidate(
                    publicReflectionListControllerProvider(widget.isbn13),
                  ),
                ),
                _ => const CommunityContentLoadingState(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReflectionList extends StatelessWidget {
  const _ReflectionList({
    required this.scrollController,
    required this.state,
    required this.onRefresh,
    required this.onOpen,
  });

  final ScrollController scrollController;
  final PublicReflectionListState state;
  final Future<void> Function() onRefresh;
  final void Function(PublicReflectionSummary reflection) onOpen;

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty) {
      return CommunityContentEmptyList(
        message: '아직 공개된 독후감이 없습니다.',
        scrollController: scrollController,
        onRefresh: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const CommunityContentPageLoader();
          }
          final reflection = state.items[index];
          return PublicReflectionCard(
            key: ValueKey(reflection.id),
            reflection: reflection,
            onTap: () => onOpen(reflection),
          );
        },
      ),
    );
  }
}
