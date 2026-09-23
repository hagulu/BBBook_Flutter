import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/author_display.dart';
import '../../../book_record/models/record_labels.dart';
import '../../../book_record/screens/book_record_screen.dart';
import '../../models/book_item.dart';
import '../../models/book_status.dart';
import '../../providers/bookshelf_providers.dart';
import 'book_cover.dart';
import 'bookshelf_async_body.dart';
import 'bookshelf_refresh_indicator.dart';
import 'recommended_books_section.dart';

/// 읽는 중 탭: READING 리스트 카드(진행률 바 + 경과일 배지).
///
/// PAUSED 상태 책도 함께 조회하되, READING 목록과 섞이지 않도록 구분선
/// 아래에 별도 섹션으로 모아서 보여준다(흐리게(dimmed) 표시는 유지).
class ReadingTabView extends ConsumerWidget {
  const ReadingTabView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(readingTabProvider);
    return BookshelfRefreshIndicator(
      recommendationStatus: BookStatus.reading,
      child: BookshelfAsyncBody<BookItem>(
        value: books,
        emptyText: '읽는 중인 책이 없습니다.',
        onRetry: () => ref.invalidate(readingTabProvider),
        emptyBuilder: (context) => const RecommendedBooksSection(
          status: BookStatus.reading,
          emptyText: '읽는 중인 책이 없습니다.',
        ),
        builder: (context, items) {
          final readingItems = [
            for (final item in items)
              if (item.status != BookStatus.paused) item,
          ];
          final pausedItems = [
            for (final item in items)
              if (item.status == BookStatus.paused) item,
          ];
          final hasPaused = pausedItems.isNotEmpty;
          // 읽는 중 목록 + (있으면) 구분 헤더 1개 + 잠시 멈춤 목록.
          final itemCount =
              readingItems.length + (hasPaused ? 1 : 0) + pausedItems.length;

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              bookshelfBottomContentPadding(context),
            ),
            itemCount: itemCount,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index < readingItems.length) {
                return _ReadingBookCard(book: readingItems[index]);
              }
              final pausedIndex = index - readingItems.length;
              if (hasPaused && pausedIndex == 0) {
                return _PausedSectionHeader(count: pausedItems.length);
              }
              final bookIndex = hasPaused ? pausedIndex - 1 : pausedIndex;
              return _ReadingBookCard(book: pausedItems[bookIndex]);
            },
          );
        },
      ),
    );
  }
}

/// 잠시 멈춤 섹션 구분 헤더. 읽는 중 목록과 시각적으로 분리되도록 위에
/// 살짝 더 넓은 간격을 두고, 아이콘 + 라벨 + 권수로 짧게 표시한다.
class _PausedSectionHeader extends StatelessWidget {
  const _PausedSectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(
            BookStatus.paused.icon,
            size: 14,
            color: AppColors.of(context).textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            '${BookStatus.paused.label} $count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.of(context).textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingBookCard extends ConsumerWidget {
  const _ReadingBookCard({required this.book});

  final BookItem book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 색을 맞출 카테고리가 애초에 없는 책이면 카테고리 목록 provider를
    // 구독하지 않는다(불필요한 리빌드/조회 방지).
    Color? categoryColor;
    if (book.displayCategoryId != null) {
      final categories = ref.watch(bookCategoriesProvider).valueOrNull;
      if (categories != null) {
        for (final category in categories) {
          if (category.id == book.displayCategoryId) {
            categoryColor = category.color;
            break;
          }
        }
      }
    }

    final card = Material(
      color: AppColors.of(context).surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookRecordScreen(userBookId: book.userBookId),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.of(context).surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.of(context).shadowSoft,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                child: BookCover(
                  imageUrl: book.coverImageUrl,
                  title: book.title,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (book.category != null) ...[
                      _CategoryBadge(
                        text: book.category!,
                        color: categoryColor,
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      book.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.of(context).textStrong,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_subtitle(book) != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(book)!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.of(context).textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    _ProgressRow(book: book),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (book.status == BookStatus.paused) {
      return Opacity(opacity: 0.5, child: card);
    }
    return card;
  }

  static String? _subtitle(BookItem book) => book.author.displayedAuthorOrNull;
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? AppColors.of(context).controlInactive).withValues(
          alpha: 0.14,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: AppColors.of(context).textBody,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.book});

  final BookItem book;

  @override
  Widget build(BuildContext context) {
    final ratio = book.progressRatio;
    final elapsedDays = _elapsedDays(book.startedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (elapsedDays != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.of(context).accentFill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '+$elapsedDays일',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.of(context).textStrong,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
            ] else
              const Spacer(),
            if (book.isAudioBook)
              // 오디오북은 페이지 기반 표현(현재 쪽/전체 쪽) 없이 퍼센트만
              // 보여준다.
              Text(
                ratio != null ? '${(ratio * 100).round()}%' : '',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.of(context).textMuted,
                ),
              )
            else if (book.effectiveTotalPages != null)
              Text(
                '${book.currentPage} / ${book.effectiveTotalPages}쪽'
                '${ratio != null ? ' (${(ratio * 100).round()}%)' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.of(context).textMuted,
                ),
              ),
          ],
        ),
        if (ratio != null) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.of(context).border,
              valueColor: AlwaysStoppedAnimation(
                AppColors.of(context).progressFill,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static int? _elapsedDays(DateTime? startedAt) {
    if (startedAt == null) return null;
    final today = DateTime.now();
    final start = DateTime(startedAt.year, startedAt.month, startedAt.day);
    final now = DateTime(today.year, today.month, today.day);
    return now.difference(start).inDays + 1;
  }
}
