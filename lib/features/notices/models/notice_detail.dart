/// `GET /api/notices/{id}`의 상세 응답(`notices-screens.md` §3-2).
class NoticeDetail {
  const NoticeDetail({
    required this.id,
    required this.title,
    required this.content,
    required this.isImportant,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String content;
  final bool isImportant;
  final DateTime createdAt;

  factory NoticeDetail.fromJson(Map<String, dynamic> json) {
    return NoticeDetail(
      id: json['id'] as int,
      title: json['title'] as String,
      content: json['content'] as String,
      isImportant: json['isImportant'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
