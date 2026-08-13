/// `GET /api/books` 검색 결과 한 권. api-doc: api-books.md.
class BookSearchItem {
  const BookSearchItem({
    required this.title,
    this.author,
    this.publisher,
    this.pubDate,
    required this.isbn,
    this.coverUrl,
    this.productUrl,
    this.category,
    this.rating,
  });

  final String title;
  final String? author;
  final String? publisher;
  final String? pubDate;
  final String isbn;
  final String? coverUrl;
  final String? productUrl;
  final String? category;

  /// 0.0 ~ 10.0(회원 평점 원본 스케일). 화면 표시는 `book-search.md` 기준
  /// 5점 만점으로 변환(`/2`)해야 한다 — [displayRating] 참고.
  final double? rating;

  double? get displayRating => rating == null ? null : rating! / 2;

  factory BookSearchItem.fromJson(Map<String, dynamic> json) {
    return BookSearchItem(
      title: json['title'] as String,
      author: json['author'] as String?,
      publisher: json['publisher'] as String?,
      pubDate: json['pubDate'] as String?,
      isbn: json['isbn'] as String,
      coverUrl: json['coverUrl'] as String?,
      productUrl: json['productUrl'] as String?,
      category: json['category'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }
}

/// `GET /api/books` 응답 전체(페이지네이션 메타 포함).
class BookSearchPage {
  const BookSearchPage({
    required this.items,
    required this.totalResults,
    required this.page,
    required this.size,
  });

  final List<BookSearchItem> items;
  final int totalResults;
  final int page;
  final int size;

  int get totalPages => (totalResults / size).ceil().clamp(1, 1 << 30);

  factory BookSearchPage.fromJson(Map<String, dynamic> json) {
    final books = (json['books'] as List<dynamic>? ?? [])
        .map((e) => BookSearchItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return BookSearchPage(
      items: books,
      totalResults: json['totalResults'] as int,
      page: json['page'] as int,
      size: json['size'] as int,
    );
  }
}
