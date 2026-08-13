/// `GET /api/books/{isbn}` 책 상세 정보. api-doc: api-books-isbn.md.
///
/// `api-books.md`의 동일 엔드포인트 설명에는 `categoryId`가 빠져 있어(문서
/// 불일치) 없을 수 있다고 보고 nullable로 파싱한다.
class BookDetail {
  const BookDetail({
    required this.title,
    this.author,
    this.publisher,
    this.pubDate,
    required this.isbn,
    this.coverUrl,
    this.productUrl,
    this.description,
    this.categoryId,
    this.category,
    this.rating,
    required this.pageCount,
  });

  final String title;
  final String? author;
  final String? publisher;
  final String? pubDate;
  final String isbn;
  final String? coverUrl;
  final String? productUrl;
  final String? description;
  final int? categoryId;
  final String? category;

  /// 0.0 ~ 10.0(회원 평점 원본 스케일). 화면 표시는 5점 만점으로 변환(`/2`).
  final double? rating;
  final int pageCount;

  double? get displayRating => rating == null ? null : rating! / 2;

  factory BookDetail.fromJson(Map<String, dynamic> json) {
    return BookDetail(
      title: json['title'] as String,
      author: json['author'] as String?,
      publisher: json['publisher'] as String?,
      pubDate: json['pubDate'] as String?,
      isbn: json['isbn'] as String,
      coverUrl: json['coverUrl'] as String?,
      productUrl: json['productUrl'] as String?,
      description: json['description'] as String?,
      categoryId: json['categoryId'] as int?,
      category: json['category'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      pageCount: json['pageCount'] as int? ?? 0,
    );
  }
}
