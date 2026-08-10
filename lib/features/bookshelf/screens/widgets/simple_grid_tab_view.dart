import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../book_record/screens/book_record_screen.dart';
import '../../models/book_item.dart';
import '../../models/book_status.dart';
import '../../providers/bookshelf_providers.dart';
import 'book_cover.dart';
import 'bookshelf_async_body.dart';
import 'bookshelf_refresh_indicator.dart';

/// 표지(2:3) + 제목 2줄 + 저자 1줄이 셀 안에 다 들어가도록 여유를 둔 비율.
/// 0.56이면 좁은 화면에서 텍스트가 넘쳐 RenderFlex 오버플로우(디버그 모드의
/// 노란/검정 빗금)가 발생해 0.46으로 낮췄다.
const _kGridAspectRatio = 0.46;

/// 읽고 싶음 / 중단 탭: 단순 그리드(표지 + 제목).
class SimpleGridTabView extends ConsumerWidget {
  const SimpleGridTabView({
    super.key,
    required this.status,
    required this.emptyText,
  });

  final BookStatus status;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = gridTabProvider(status);
    final books = ref.watch(provider);
    return BookshelfRefreshIndicator(
      child: BookshelfAsyncBody<BookItem>(
        value: books,
        emptyText: emptyText,
        onRetry: () => ref.invalidate(provider),
        builder: (context, items) {
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              childAspectRatio: _kGridAspectRatio,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _GridBookCard(book: items[index]),
          );
        },
      ),
    );
  }
}

class _GridBookCard extends StatelessWidget {
  const _GridBookCard({required this.book});

  final BookItem book;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookRecordScreen(userBookId: book.userBookId),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCover(imageUrl: book.coverImageUrl, title: book.title),
          const SizedBox(height: 6),
          Text(
            book.title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.titleText,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (book.author != null)
            Text(
              book.author!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.tertiaryText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
