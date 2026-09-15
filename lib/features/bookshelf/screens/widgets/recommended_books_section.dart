import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/author_display.dart';
import '../../../book_detail/screens/book_detail_screen.dart';
import '../../../book_record/screens/book_record_screen.dart';
import '../../models/book_recommendation.dart';
import '../../models/book_status.dart';
import '../../providers/bookshelf_providers.dart';
import 'book_cover.dart';
import 'bookshelf_refresh_indicator.dart';

/// 읽는 중/읽을 책 탭이 비어 있을 때 [BookshelfAsyncBody.emptyBuilder]로
/// 대신 노출하는 영역. 추천 결과가 있으면 그것만 보여주고, 아직 없거나
/// (로딩·실패·빈 응답) API가 책이 없는 그룹만 내려주면 그때만 기존 빈
/// 문구([emptyText])로 대체한다 — "추천 실패가 책장 기능에 영향을 주지
/// 않는다"는 요구에 대응하는 fallback이다.
class RecommendedBooksSection extends ConsumerWidget {
  const RecommendedBooksSection({
    super.key,
    required this.status,
    required this.emptyText,
  });

  final BookStatus status;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref
        .watch(bookRecommendationsProvider(status))
        .valueOrNull
        ?.where((group) => group.books.isNotEmpty)
        .toList();
    final hasRecommendations = groups != null && groups.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 24, 16, bookshelfFabBottomPadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: hasRecommendations
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < groups.length; i++) ...[
                        if (i > 0) const SizedBox(height: 20),
                        _RecommendationGroup(group: groups[i]),
                      ],
                    ],
                  )
                : Center(
                    child: Text(
                      emptyText,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.of(context).textMuted),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _RecommendationGroup extends StatelessWidget {
  const _RecommendationGroup({required this.group});

  final BookRecommendationGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            group.message,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              height: 1.3,
              color: AppColors.of(context).textStrong,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          // 책이 3권 미만이어도(api-doc: 제외 후 후보 부족 시 가능한 만큼만
          // 반환) 표지 하나가 화면 폭을 다 차지하지 않도록 항상 3칸 폭을
          // 유지하고 남는 칸은 비워 둔다.
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: i < group.books.length
                    ? _RecommendedBookCard(book: group.books[i])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RecommendedBookCard extends StatelessWidget {
  const _RecommendedBookCard({required this.book});

  final RecommendedBook book;

  // 다시읽기 추천 항목은 책장에 이미 있는 책 자체를 그대로 추천하므로
  // userBookId로 기존 책 기록 상세로 보낸다(api-doc: userBookId가 있으면
  // isbn13은 커스텀 등록 책이라 null일 수 있어 식별 기준이 아니다). 그 외
  // (YES24 베스트셀러 추천)는 isbn13으로 검색 결과와 동일한 책 상세 화면을
  // 재사용한다.
  void _open(BuildContext context) {
    final userBookId = book.userBookId;
    if (userBookId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookRecordScreen(userBookId: userBookId)),
      );
      return;
    }
    final isbn13 = book.isbn13;
    if (isbn13 != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookDetailScreen(isbn: isbn13)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCover(imageUrl: book.coverImageUrl, title: book.title),
          const SizedBox(height: 6),
          Text(
            book.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.of(context).textStrong,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (book.author.displayedAuthorOrNull case final author?)
            Text(
              author,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.of(context).textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
