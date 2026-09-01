import 'my_content_book.dart';

/// `GET /api/me/discussions`의 목록 항목(`my-content-screens.md` §4-4).
class MyDiscussionSummary {
  const MyDiscussionSummary({
    required this.id,
    required this.isbn13,
    required this.book,
    required this.title,
    required this.previewText,
    required this.isSpoiler,
    required this.isHidden,
    required this.isClosed,
    required this.createdAt,
  });

  final int id;
  final String isbn13;
  final MyContentBookRef? book;

  /// isHidden이 true이면 서버 응답 자체가 null.
  final String? title;

  /// isHidden이 true이면 서버 응답 자체가 null.
  final String? previewText;
  final bool isSpoiler;
  final bool isHidden;
  final bool isClosed;
  final DateTime createdAt;

  factory MyDiscussionSummary.fromJson(Map<String, dynamic> json) {
    return MyDiscussionSummary(
      id: json['id'] as int,
      isbn13: json['isbn13'] as String,
      book: myContentBookRefOrNullFromJson(json['book']),
      title: json['title'] as String?,
      previewText: json['previewText'] as String?,
      isSpoiler: json['isSpoiler'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      isClosed: json['isClosed'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
