import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/community_content.dart';
import '../../discussion/utils/discussion_date.dart';
import '../models/notice_summary.dart';
import '../providers/notices_providers.dart';
import 'notice_detail_screen.dart';

/// 공지사항 목록(`notices-screens.md` §1).
class NoticesListScreen extends ConsumerStatefulWidget {
  const NoticesListScreen({super.key});

  @override
  ConsumerState<NoticesListScreen> createState() => _NoticesListScreenState();
}

class _NoticesListScreenState extends ConsumerState<NoticesListScreen> {
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
      ref.read(noticeListControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(noticeListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('공지사항'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          AsyncData(:final value) => _NoticeList(
            scrollController: _scrollController,
            items: value.items,
            isLoadingMore: value.isLoadingMore,
            loadMoreError: value.loadMoreError,
            onRetryLoadMore: () =>
                ref.read(noticeListControllerProvider.notifier).retryLoadMore(),
          ),
          AsyncError() => CommunityContentErrorState(
            message: '공지사항을 불러오지 못했습니다',
            onRetry: () => ref.invalidate(noticeListControllerProvider),
          ),
          _ => const CommunityContentLoadingState(),
        },
      ),
    );
  }
}

class _NoticeList extends StatelessWidget {
  const _NoticeList({
    required this.scrollController,
    required this.items,
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onRetryLoadMore,
  });

  final ScrollController scrollController;
  final List<NoticeSummary> items;
  final bool isLoadingMore;
  final bool loadMoreError;
  final VoidCallback onRetryLoadMore;

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
              '등록된 공지사항이 없습니다',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
        ],
      );
    }

    // 카드 하나로 감싸는 모양은 유지하되, 누적된 항목을 전부 즉시 빌드하는
    // Column 대신 화면 주변 행만 지연 생성하는 ListView.builder를 쓴다 —
    // 각 행이 자기 위치(첫/마지막)에 맞는 모서리·테두리를 스스로 그린다.
    return ListView.builder(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: items.length + (isLoadingMore || loadMoreError ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return loadMoreError
              ? _LoadMoreError(onRetry: onRetryLoadMore)
              : const CommunityContentPageLoader();
        }
        return _NoticeRow(
          notice: items[index],
          isFirst: index == 0,
          isLast: index == items.length - 1,
        );
      },
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.notice,
    required this.isFirst,
    required this.isLast,
  });

  final NoticeSummary notice;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(16) : Radius.zero,
      bottom: isLast ? const Radius.circular(16) : Radius.zero,
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: InkWell(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => NoticeDetailScreen(noticeId: notice.id),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: borderRadius,
            border: Border(
              top: const BorderSide(color: AppColors.border),
              bottom: isLast
                  ? const BorderSide(color: AppColors.border)
                  : BorderSide.none,
              left: const BorderSide(color: AppColors.border),
              right: const BorderSide(color: AppColors.border),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDiscussionDate(notice.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                PhosphorIconsRegular.caretRight,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '공지사항을 불러오지 못했습니다',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
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
