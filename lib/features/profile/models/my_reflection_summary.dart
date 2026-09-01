import 'my_content_book.dart';

/// `GET /api/me/reflections`의 목록 항목(`my-content-screens.md` §2-4).
class MyReflectionSummary {
  const MyReflectionSummary({
    required this.id,
    required this.isbn13,
    required this.book,
    required this.title,
    required this.previewText,
    required this.isPublic,
    required this.isHidden,
    required this.createdAt,
  });

  final int id;
  final String? isbn13;
  final MyContentBookRef? book;

  /// isHidden이 true이면 서버 응답 자체가 null.
  final String? title;

  /// isHidden이 true이면 서버 응답 자체가 null.
  final String? previewText;
  final bool isPublic;
  final bool isHidden;
  final DateTime createdAt;

  factory MyReflectionSummary.fromJson(Map<String, dynamic> json) {
    return MyReflectionSummary(
      id: json['id'] as int,
      isbn13: json['isbn13'] as String?,
      book: myContentBookRefOrNullFromJson(json['book']),
      title: json['title'] as String?,
      previewText: json['previewText'] as String?,
      isPublic: json['isPublic'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
