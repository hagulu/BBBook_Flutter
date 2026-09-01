import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../bookshelf/screens/widgets/book_cover.dart';
import '../../models/my_content_book.dart';

/// "내가 작성한 콘텐츠" 4개 목록 카드가 공유하는 레이아웃.
///
/// 책 제목·저자가 맨 윗줄을 한 줄로 차지하고, 그 아래에 책 표지(고정 폭)와
/// 콘텐츠 영역이 나란히 배치된다. 표지 폭·비율을 4개 화면에서 동일하게
/// 맞추기 위한 공용 스캐폴드다.
class MyContentCardLayout extends StatelessWidget {
  const MyContentCardLayout({
    super.key,
    required this.book,
    required this.content,
    this.coverOverlay,
    this.onBookTap,
    this.dateLabel,
  });

  /// 책 표지 고정 폭(모든 목록 화면 공통, 2:3 비율은 [BookCover]가 담당).
  static const double coverWidth = 64;

  final MyContentBookRef? book;

  /// 표지 오른쪽에 배치되는 화면별 콘텐츠(제목·미리보기 등, 작성일 제외).
  final Widget content;

  /// 표지 위에 겹치는 배지(예: 토론 마감 오버레이).
  final Widget? coverOverlay;

  /// 지정하면 책 제목 줄과 표지만 탭 가능해진다(리뷰 목록처럼 콘텐츠는
  /// 탭할 수 없고 책 정보로만 이동하는 화면 전용). null이면 두 영역 모두
  /// 정적으로 표시된다(카드 전체 탭은 상위 [CommunityContentCard]가 담당).
  final VoidCallback? onBookTap;

  /// 카드 오른쪽 아래에 고정 배치되는 작성일. [content]의 줄 수와 무관하게
  /// 항상 같은 높이(표지 하단)에 위치하도록 [content]와 분리해서 받는다.
  /// null이면(숨김 항목 등) 표시하지 않는다.
  final String? dateLabel;

  @override
  Widget build(BuildContext context) {
    final book = this.book;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (book != null) ...[
          _BookTitleRow(book: book, onTap: onBookTap),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
        ],
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (book != null) ...[
                _BookCoverThumb(
                  book: book,
                  overlay: coverOverlay,
                  onTap: onBookTap,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: content),
                    if (dateLabel != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          dateLabel!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BookTitleRow extends StatelessWidget {
  const _BookTitleRow({required this.book, this.onTap});

  final MyContentBookRef book;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      [book.title, ?book.author].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
      ),
    );

    if (onTap == null) return text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: text,
    );
  }
}

class _BookCoverThumb extends StatelessWidget {
  const _BookCoverThumb({required this.book, this.overlay, this.onTap});

  final MyContentBookRef book;
  final Widget? overlay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cover = Stack(
      children: [
        BookCover(imageUrl: book.coverImageUrl, title: book.title),
        if (overlay != null) Positioned.fill(child: overlay!),
      ],
    );

    return SizedBox(
      width: MyContentCardLayout.coverWidth,
      child: onTap == null
          ? cover
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: cover,
            ),
    );
  }
}
