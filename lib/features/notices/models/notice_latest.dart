/// `GET /api/notices/latest` 응답(`api-notices-latest-get.md`).
/// 최근 7일 이내 최신 일반 공지의 id만 담는다. 대상이 없으면 [id]가 null.
class NoticeLatest {
  const NoticeLatest({required this.id});

  final int? id;

  factory NoticeLatest.fromJson(Map<String, dynamic> json) {
    final exists = json['exists'] as bool? ?? false;
    return NoticeLatest(id: exists ? json['id'] as int? : null);
  }
}
