import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/author_display.dart';
import '../../../book_record/screens/book_record_screen.dart';
import '../../models/book_item.dart';
import '../../models/book_status.dart';
import '../../providers/bookshelf_providers.dart';
import 'book_cover.dart';
import 'bookshelf_async_body.dart';
import 'bookshelf_refresh_indicator.dart';

/// 읽는 중 탭: READING 리스트 카드(진행률 바 + 경과일 배지).
///
/// PAUSED 상태 책도 함께 조회해 흐리게(dimmed) 표시한다(`bookshelf.md`).
class ReadingTabView extends ConsumerWidget {
  const ReadingTabView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(readingTabProvider);
    return BookshelfRefreshIndicator(
      child: BookshelfAsyncBody<BookItem>(
        value: books,
        emptyText: '읽는 중인 책이 없습니다.',
        onRetry: () => ref.invalidate(readingTabProvider),
        builder: (context, items) {
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              16,
              8,
              16,
              bookshelfFabBottomPadding,
            ),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _ReadingBookCard(book: items[index]),
          );
        },
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
      color: AppColors.surface,
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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowSoft,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textStrong,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_subtitle(book) != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(book)!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
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

  static String? _subtitle(BookItem book) {
    final author = book.author;
    return author != null && author.isNotEmpty ? displayAuthor(author) : null;
  }
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
        color: (color ?? AppColors.controlInactive).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textBody,
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
                  color: AppColors.accentFill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '+$elapsedDays일',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textStrong,
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
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              )
            else if (book.effectiveTotalPages != null)
              Text(
                '${book.currentPage} / ${book.effectiveTotalPages}쪽'
                '${ratio != null ? ' (${(ratio * 100).round()}%)' : ''}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
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
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.progressFill),
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
