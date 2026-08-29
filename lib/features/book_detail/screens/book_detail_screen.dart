import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/author_display.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../book_record/screens/widgets/star_rating.dart';
import '../../bookshelf/models/book_status.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../bookshelf/screens/widgets/book_cover.dart';
import '../providers/book_detail_providers.dart';
import 'widgets/add_status_dialog.dart';
import 'widgets/community_reviews_section.dart';
import 'widgets/finish_options_dialog.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 검색 결과 경유 책 상세 화면(`/books/[isbn]` 대응, book-detail.md).
/// `BookSearchScreen`의 검색 결과 카드에서 `Navigator.push`로 진입한다.
///
/// 커뮤니티 리뷰와 공개 독후감·주제 토론 진입점을 책 정보 아래에 구성한다.
class BookDetailScreen extends ConsumerStatefulWidget {
  const BookDetailScreen({super.key, required this.isbn});

  final String isbn;

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
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
          .read(bookshelfRepositoryProvider)
          .createIsbnBook(
            isbn13: data.detail.isbn,
            title: data.detail.title,
            author: data.detail.author,
            publisher: data.detail.publisher,
            totalPages: data.detail.pageCount == 0
                ? null
                : data.detail.pageCount,
            coverImageUrl: data.detail.coverUrl,
            categoryId: data.detail.categoryId,
            category: data.detail.category,
            status: status,
            sourceType: options?.sourceType?.apiValue,
            myRating: options?.myRating,
            shortReview: options?.shortReview,
            difficulty: options?.difficulty?.apiValue,
            finishedAt: options?.finishedAt == null
                ? null
                : _formatDate(options!.finishedAt!),
          );
      if (!mounted) return;
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
      ref
          .read(bookDetailControllerProvider(widget.isbn).notifier)
          .markAddedToShelf(result.userBookId);
      // serverId는 서버 반영 여부일 뿐이라 로컬 저장 모드·오프라인에서는
      // 계속 null이다. 담기 자체는 로컬 저장으로 확정된다.
      AppSnackBar.success(context, '서재에 추가되었습니다.');
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        ref.invalidate(bookDetailControllerProvider(widget.isbn));
      }
      if (mounted) AppSnackBar.error(context, e.message);
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
      AppSnackBar.error(context, '구매 페이지를 열 수 없습니다.');
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
    Widget? bottomBar;
    if (state.hasValue) {
      final value = state.value!;
      body = AppLoadingOverlay(
        isLoading: state.isLoading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroSection(data: value),
              const SizedBox(height: 24),
              CommunityReviewsSection(
                isbn13: value.detail.isbn,
                bookTitle: value.detail.title,
              ),
            ],
          ),
        ),
      );
      bottomBar = _BottomActionBar(
        data: value,
        onAddToShelf: () => _addToShelf(value),
        onBuy:
            value.detail.productUrl == null || value.detail.productUrl!.isEmpty
            ? null
            : () => _openProductUrl(value.detail.productUrl!),
      );
    } else if (state.hasError) {
      body = _ErrorBody(
        onRetry: () =>
            ref.invalidate(bookDetailControllerProvider(widget.isbn)),
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('검색으로'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: body,
      bottomNavigationBar: bottomBar,
    );
  }
}

/// 서재 담기/구매 버튼을 화면 하단에 고정하는 CTA 바.
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.data,
    required this.onAddToShelf,
    required this.onBuy,
  });

  final BookDetailData data;
  final VoidCallback onAddToShelf;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.pageBackground,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
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
                icon: const Icon(
                  PhosphorIconsRegular.shoppingCartSimple,
                  size: 18,
                ),
                label: const Text('구매'),
              ),
            ),
          ],
        ),
      ),
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
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.data});

  final BookDetailData data;

  @override
  Widget build(BuildContext context) {
    final detail = data.detail;
    final metaParts = <String>[
      if (detail.publisher != null && detail.publisher!.isNotEmpty)
        detail.publisher!,
      if (detail.pageCount > 0) '${detail.pageCount}쪽',
      if (detail.pubDate != null && detail.pubDate!.isNotEmpty) detail.pubDate!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 160,
          child: BookCover(imageUrl: detail.coverUrl, title: detail.title),
        ),
        const SizedBox(height: 16),
        if (detail.category != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accentSurface.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              detail.category!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textBody,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          detail.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: AppColors.textStrong,
          ),
        ),
        if (detail.author != null && detail.author!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            displayAuthor(detail.author!),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
        if (metaParts.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            metaParts.join(' · '),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
        if (detail.displayRating != null) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StarRatingDisplay(rating: detail.displayRating!, size: 15),
              const SizedBox(width: 6),
              Text(
                detail.rating!.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textStrong,
                ),
              ),
            ],
          ),
        ],
        if (detail.description != null && detail.description!.isNotEmpty) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: Text(
              detail.description!,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textBody,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
