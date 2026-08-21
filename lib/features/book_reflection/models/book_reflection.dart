/// 독후감(`book_reflection`) 로컬 도메인 모델.
///
/// `id`는 지금은 항상 서버 ID와 같다 — 로컬 오프라인 생성(`BookNote`처럼
/// `server_id`를 분리해 로컬 임시 음수 ID를 쓰는 방식)은 편집기 기능이
/// 아직 없어 아직 필요 없다. `isDirty`는 스키마에는 있지만(추후 로컬 편집
/// 기능을 붙일 때 대비) 이 화면에서는 항상 false로 읽힌다.
class BookReflection {
  const BookReflection({
    required this.id,
    required this.userBookId,
    required this.reflectionType,
    required this.title,
    required this.contentJson,
    required this.contentText,
    required this.isPublic,
    required this.isHidden,
    required this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.isDirty,
  });

  final int id;
  final int userBookId;

  /// 예: USER_WRITTEN, AI_GENERATED. 화면에서 이 값으로 분기하는 기능은
  /// 아직 없다(포팅 문서 기준 DRAFT/AI_GENERATED UI 미구현 — 확인 필요 항목).
  final String reflectionType;
  final String? title;

  /// Tiptap(ProseMirror) JSON 문서. 리치 텍스트 렌더링은 아직 붙이지 않아
  /// 현재 화면에서는 사용하지 않고 [contentText]만 보여준다.
  final Map<String, dynamic>? contentJson;

  /// 검색/미리보기용 순수 텍스트.
  final String? contentText;
  final bool isPublic;

  /// 관리자에 의한 숨김 처리 여부. true면 title/contentJson/contentText가
  /// null로 내려온다(서버 정책).
  final bool isHidden;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDirty;
}
