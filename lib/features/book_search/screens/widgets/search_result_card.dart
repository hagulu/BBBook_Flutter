import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/author_display.dart';
import '../../../bookshelf/screens/widgets/book_cover.dart';
import '../../models/book_search_item.dart';

/// 검색 결과 카드(표지/제목/저자/출판사/출간일). book-search.md 기준.
class SearchResultCard extends StatelessWidget {
  const SearchResultCard({super.key, required this.item, required this.onTap});

  final BookSearchItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: BookCover(imageUrl: item.coverUrl, title: item.title),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        height: 1.35,
                        color: AppColors.textStrong,
                      ),
                    ),
                    if (item.author != null && item.author!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        displayAuthor(item.author!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                    if (item.publisher != null || item.pubDate != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (item.publisher != null && item.publisher!.isNotEmpty)
                            item.publisher!,
                          if (item.pubDate != null && item.pubDate!.isNotEmpty)
                            item.pubDate!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
