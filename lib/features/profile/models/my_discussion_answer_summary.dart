import 'my_content_book.dart';

/// `GET /api/me/discussion-answers`의 목록 항목(`my-content-screens.md` §5-4).
class MyDiscussionAnswerSummary {
  const MyDiscussionAnswerSummary({
    required this.id,
    required this.topicId,
    required this.topicTitle,
    required this.isbn13,
    required this.book,
    required this.content,
    required this.isHidden,
    required this.createdAt,
  });

  final int id;
  final int topicId;

  /// 원본 토론이 삭제되었거나 관리자에 의해 숨김 처리된 경우 null.
  final String? topicTitle;
  final String? isbn13;
  final MyContentBookRef? book;

  /// isHidden이 true이면 서버 응답 자체가 null.
  final String? content;
  final bool isHidden;
  final DateTime createdAt;

  factory MyDiscussionAnswerSummary.fromJson(Map<String, dynamic> json) {
    return MyDiscussionAnswerSummary(
      id: json['id'] as int,
      topicId: json['topicId'] as int,
      topicTitle: json['topicTitle'] as String?,
      isbn13: json['isbn13'] as String?,
      book: myContentBookRefOrNullFromJson(json['book']),
      content: json['content'] as String?,
      isHidden: json['isHidden'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
