/// `tag` 로컬 행. 자체 dirty 추적이 없다 — 태그 생성/복원은 항상
/// `POST .../tags`(매핑 추가)의 부수 효과로만 일어난다([TagRepository] 참고).
class LocalTag {
  const LocalTag({
    required this.id,
    required this.serverId,
    required this.name,
  });

  final int id;
  final int? serverId;
  final String name;
}

/// `user_book_tag_map` 로컬 행. [userBookId]/[tagId]는 모두 로컬 PK다.
class TagMapping {
  const TagMapping({
    required this.id,
    required this.serverId,
    required this.userBookId,
    required this.tagId,
    required this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.isDirty,
  });

  final int id;
  final int? serverId;
  final int userBookId;
  final int tagId;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDirty;
}
