import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../book_record/screens/widgets/star_rating.dart';
import '../../bookshelf/models/book_status.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../bookshelf/screens/widgets/book_cover.dart';
import '../models/book_detail.dart';
import '../providers/book_detail_providers.dart';
import 'widgets/add_status_dialog.dart';
import 'widgets/community_reviews_section.dart';
import 'widgets/finish_options_dialog.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 검색 결과 경유 책 상세 화면(`/books/[isbn]` 대응, book-detail.md).
/// `BookSearchScreen`의 검색 결과 카드에서 `Navigator.push`로 진입한다.
///
/// 토론/공개 독후감 탭은 해당 기능(discussions/reflection-editor)이 아직
/// 이관되지 않아 이번 범위에서 제외한다(사용자 확인 사항) — 커뮤니티 리뷰
/// 섹션만 탭 구분 없이 바로 붙인다.
class BookDetailScreen extends ConsumerStatefulWidget {
  const BookDetailScreen({super.key, required this.isbn});

  final String isbn;

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  bool _handleScrollNotification(ScrollNotification notification, String isbn13) {
    final metrics = notification.metrics;
    if (metrics.axis == Axis.vertical &&
        metrics.pixels >= metrics.maxScrollExtent - 300) {
      final reviewsState = ref.read(reviewsControllerProvider(isbn13)).valueOrNull;
      if (reviewsState != null && reviewsState.hasNext && !reviewsState.isLoadingMore) {
        ref.read(reviewsControllerProvider(isbn13).notifier).loadMore();
      }
    }
    return false;
  }

  Future<void> _addToShelf(BookDetailData data) async {
    final status = await showAddStatusDialog(context);
    if (status == null || !mounted) return;

    FinishOptionsResult? options;
    if (status == BookStatus.finished) {
      options = await showFinishOptionsDialog(context);
      if (options == null || !mounted) return;
    }

    AppLoading.show(context);
    try {
      final result = await ref
          .read(bookDetailApiProvider)
          .addToBookshelf(
            isbn13: data.detail.isbn,
            status: status.apiValue,
            sourceType: options?.sourceType?.apiValue,
            myRating: options?.myRating,
            shortReview: options?.shortReview,
            difficulty: options?.difficulty?.apiValue,
            finishedAt: options?.finishedAt == null
                ? null
                : _formatDate(options!.finishedAt!),
          );
      await ref
          .read(bookshelfSyncControllerProvider.notifier)
          .ensureSynced(result.userBookId);
      if (!mounted) return;
      ref
          .read(bookDetailControllerProvider(widget.isbn).notifier)
          .markAddedToShelf(result.userBookId);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('서재에 추가되었습니다.')));
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        ref.invalidate(bookDetailControllerProvider(widget.isbn));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      AppLoading.hide();
    }
  }

  Future<void> _openProductUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    bool launched;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('구매 페이지를 열 수 없습니다.')));
    }
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookDetailControllerProvider(widget.isbn));

    // book_record_screen.dart와 동일한 패턴: hasValue를 우선 확인해 409 재조회
    // 등으로 잠깐 loading으로 전환되는 동안에도(이전 값이 있으면) 전체 화면을
    // "불러오는 중"으로 덮어쓰지 않고 오버레이만 얹는다.
    Widget body;
    if (state.hasValue) {
      final value = state.value!;
      body = AppLoadingOverlay(
        isLoading: state.isLoading,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => _handleScrollNotification(n, value.detail.isbn),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroSection(
                  data: value,
                  onAddToShelf: () => _addToShelf(value),
                  onBuy: value.detail.productUrl == null || value.detail.productUrl!.isEmpty
                      ? null
                      : () => _openProductUrl(value.detail.productUrl!),
                ),
                const SizedBox(height: 24),
                CommunityReviewsSection(isbn13: value.detail.isbn),
              ],
            ),
          ),
        ),
      );
    } else if (state.hasError) {
      body = _ErrorBody(
        onRetry: () => ref.invalidate(bookDetailControllerProvider(widget.isbn)),
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('검색으로'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.titleText,
        elevation: 0,
      ),
      body: body,
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '불러오지 못했습니다.',
            style: TextStyle(color: AppColors.tertiaryText),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.data,
    required this.onAddToShelf,
    required this.onBuy,
  });

  final BookDetailData data;
  final VoidCallback onAddToShelf;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final detail = data.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: BookCover(imageUrl: detail.coverUrl, title: detail.title),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (detail.category != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accentLight.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        detail.category!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.bodyText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    detail.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: AppColors.titleText,
                    ),
                  ),
                  if (detail.author != null && detail.author!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      detail.author!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.tertiaryText,
                      ),
                    ),
                  ],
                  if (detail.displayRating != null) ...[
                    const SizedBox(height: 8),
                    StarRatingDisplay(rating: detail.displayRating!, size: 15),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: data.existsInShelf ? null : onAddToShelf,
                icon: Icon(
                  data.existsInShelf
                      ? PhosphorIconsFill.checkCircle
                      : PhosphorIconsRegular.bookmarkSimple,
                  size: 18,
                ),
                label: Text(data.existsInShelf ? '이미 서재에 있음' : '서재 담기'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onBuy,
                icon: const Icon(PhosphorIconsRegular.shoppingCartSimple, size: 18),
                label: const Text('구매'),
              ),
            ),
          ],
        ),
        if (detail.description != null && detail.description!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            detail.description!,
            style: const TextStyle(fontSize: 14, color: AppColors.bodyText, height: 1.5),
          ),
        ],
        const SizedBox(height: 16),
        _MetaGrid(detail: detail),
      ],
    );
  }
}

class _MetaGrid extends StatelessWidget {
  const _MetaGrid({required this.detail});

  final BookDetail detail;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (detail.publisher != null && detail.publisher!.isNotEmpty)
        ('출판사', detail.publisher!),
      if (detail.pageCount > 0) ('쪽수', '${detail.pageCount}쪽'),
      if (detail.pubDate != null && detail.pubDate!.isNotEmpty)
        ('출간일', detail.pubDate!),
      ('ISBN', detail.isbn),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    rows[i].$1,
                    style: const TextStyle(fontSize: 12, color: AppColors.tertiaryText),
                  ),
                ),
                Expanded(
                  child: Text(
                    rows[i].$2,
                    style: const TextStyle(fontSize: 13, color: AppColors.bodyText),
                  ),
                ),
              ],
            ),
            if (i != rows.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
