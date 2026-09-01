import 'my_content_book.dart';

/// `GET /api/me/reviews`의 목록 항목(`my-content-screens.md` §3-4).
class MyReviewSummary {
  const MyReviewSummary({
    required this.id,
    required this.isbn13,
    required this.book,
    required this.rating,
    required this.content,
    required this.isSpoiler,
    required this.isHidden,
    required this.createdAt,
  });

  final int id;
  final String isbn13;
  final MyContentBookRef? book;

  /// isHidden이 true이면 서버 응답 자체가 null.
  final double? rating;

  /// isHidden이 true이면 서버 응답 자체가 null.
  final String? content;
  final bool isSpoiler;
  final bool isHidden;
  final DateTime createdAt;

  factory MyReviewSummary.fromJson(Map<String, dynamic> json) {
    return MyReviewSummary(
      id: json['id'] as int,
      isbn13: json['isbn13'] as String,
      book: myContentBookRefOrNullFromJson(json['book']),
      rating: (json['rating'] as num?)?.toDouble(),
      content: json['content'] as String?,
      isSpoiler: json['isSpoiler'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
