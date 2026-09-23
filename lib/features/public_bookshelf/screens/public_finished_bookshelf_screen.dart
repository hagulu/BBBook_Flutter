import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/community_content.dart';
import '../../book_detail/screens/book_detail_screen.dart';
import '../../bookshelf/screens/widgets/book_cover.dart';
import '../models/public_finished_book.dart';
import '../providers/public_bookshelf_providers.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(
          widget.nickname == null ? '완독 책장' : '${widget.nickname}의 완독 책장',
        ),
        backgroundColor: AppColors.of(context).pageBackground,
        foregroundColor: AppColors.of(context).textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: switch (state) {
          AsyncData(:final value) => _FinishedGrid(
            scrollController: _scrollController,
            items: value.items,
            isLoadingMore: value.isLoadingMore,
            onTapBook: _openBook,
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
  });

  final ScrollController scrollController;
  final List<PublicFinishedBook> items;
  final bool isLoadingMore;
  final void Function(PublicFinishedBook book) onTapBook;

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
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              childAspectRatio: 0.46,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _FinishedBookCard(
                book: items[index],
                onTap: () => onTapBook(items[index]),
              ),
              childCount: items.length,
            ),
          ),
        ),
        if (isLoadingMore)
          const SliverToBoxAdapter(child: CommunityContentPageLoader()),
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
        ),
      ],
    );
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
