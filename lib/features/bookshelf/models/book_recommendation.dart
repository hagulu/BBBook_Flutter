/// `GET /api/me/recommendations/books` 응답 모델.
///
/// 추천 카테고리·문구 선정, 베스트셀러 조회는 모두 서버에서 처리한다(api-doc).
/// 앱은 응답을 그대로 노출하며 목록/책 개수를 임의로 가공하지 않는다.
class BookRecommendationGroup {
  const BookRecommendationGroup({
    required this.message,
    required this.categoryId,
    required this.categoryName,
    required this.books,
  });

  final String message;

  /// 다시읽기 추천 목록은 카테고리 없이 책장의 책 자체를 그대로 추천하므로
  /// null이다(api-doc).
  final int? categoryId;
  final String? categoryName;
  final List<RecommendedBook> books;

  factory BookRecommendationGroup.fromJson(Map<String, dynamic> json) {
    return BookRecommendationGroup(
      message: json['message'] as String,
      categoryId: json['categoryId'] as int?,
      categoryName: json['categoryName'] as String?,
      books: (json['books'] as List<dynamic>? ?? [])
          .map((e) => RecommendedBook.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RecommendedBook {
  const RecommendedBook({
    this.userBookId,
    this.isbn13,
    required this.title,
    this.author,
    this.publisher,
    this.coverImageUrl,
  });

  /// 다시읽기 추천 항목에서만 값이 있다(책장에 이미 있는 책 자체를 그대로
  /// 추천). YES24 베스트셀러 추천 항목은 null이다(api-doc).
  final int? userBookId;

  /// 다시읽기 추천 항목이 커스텀 등록 책(ISBN 미연결)이면 null일 수 있다 —
  /// 그 경우 [userBookId]로 식별한다(api-doc).
  final String? isbn13;
  final String title;
  final String? author;
  final String? publisher;
  final String? coverImageUrl;

  factory RecommendedBook.fromJson(Map<String, dynamic> json) {
    return RecommendedBook(
      userBookId: json['userBookId'] as int?,
      isbn13: json['isbn13'] as String?,
      title: json['title'] as String,
      author: json['author'] as String?,
      publisher: json['publisher'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
    );
  }
}
