/// `GET /api/notices`의 목록 항목(`notices-screens.md` §3-1).
class NoticeSummary {
  const NoticeSummary({
    required this.id,
    required this.title,
    required this.isImportant,
    required this.createdAt,
  });

  final int id;
  final String title;
  final bool isImportant;
  final DateTime createdAt;

  factory NoticeSummary.fromJson(Map<String, dynamic> json) {
    return NoticeSummary(
      id: json['id'] as int,
      title: json['title'] as String,
      isImportant: json['isImportant'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// `GET /api/notices` 응답 페이지(`notices-screens.md` §3-1).
class NoticeSummaryPage {
  const NoticeSummaryPage({
    required this.items,
    required this.nextCursor,
    required this.hasNext,
  });

  final List<NoticeSummary> items;
  final int? nextCursor;
  final bool hasNext;

  factory NoticeSummaryPage.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(NoticeSummary.fromJson)
        .toList();
    return NoticeSummaryPage(
      items: items,
      nextCursor: json['nextCursor'] as int?,
      hasNext: json['hasNext'] as bool,
    );
  }
}
