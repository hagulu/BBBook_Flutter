/// 독후감(`book_reflection`) 로컬 도메인 모델.
///
/// `id`는 로컬 PK, [serverId]는 서버 PK다. 신규 작성은 음수 로컬 PK로 즉시
/// 저장되고 서버 push 성공 뒤에도 `id`를 유지해 화면 참조가 끊기지 않는다.
class BookReflection {
  const BookReflection({
    required this.id,
    required this.serverId,
    required this.clientRequestId,
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

  /// 서버에 반영된 실제 독후감 ID. null이면 아직 서버에 생성되지 않은
  /// 로컬 우선 행이며 [id]는 음수 임시 PK다.
  final int? serverId;

  /// 로컬 생성 시 한 번 발급해 서버 CREATE 재시도마다 재사용하는 멱등 UUID.
  final String? clientRequestId;
  final int userBookId;

  /// 예: USER_WRITTEN, AI_GENERATED. 화면에서 이 값으로 분기하는 기능은
  /// 아직 없다(포팅 문서 기준 DRAFT/AI_GENERATED UI 미구현 — 확인 필요 항목).
  final String reflectionType;
  final String? title;

  /// Quill Delta 또는 레거시 Tiptap 문서. 화면은 직접 해석하지 않고
  /// `BookReflectionContentAdapter`를 통해 Quill Document로 복원한다.
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

class BookReflectionDraft {
  const BookReflectionDraft({
    required this.title,
    required this.contentJson,
    required this.contentText,
    required this.isPublic,
  });

  final String title;
  final Map<String, dynamic> contentJson;
  final String contentText;
  final bool isPublic;
}

/// 독후감 CREATE/PATCH 응답 중 로컬 확정에 필요한 공통 필드.
class BookReflectionServerResult {
  const BookReflectionServerResult({
    required this.id,
    required this.userBookId,
    required this.reflectionType,
    required this.title,
    required this.contentJson,
    required this.contentText,
    required this.isPublic,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int userBookId;
  final String? reflectionType;
  final String title;
  final Map<String, dynamic> contentJson;
  final String contentText;
  final bool isPublic;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory BookReflectionServerResult.fromJson(Map<String, dynamic> json) {
    return BookReflectionServerResult(
      id: json['id'] as int,
      userBookId: json['userBookId'] as int,
      reflectionType: json['reflectionType'] as String?,
      title: json['title'] as String,
      contentJson: Map<String, dynamic>.from(json['contentJson'] as Map),
      contentText: json['contentText'] as String,
      isPublic: json['isPublic'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// 독후감 본문 이미지 하나의 "서버 URL ↔ 로컬 사본" 짝
/// (`reflection_image_local` 한 행). 서버에는 존재하지 않는 로컬 전용
/// 정보이며, 실제 파일은 `reflectionImageStore`가 관리한다.
class ReflectionImageLink {
  const ReflectionImageLink({
    required this.reflectionId,
    required this.remoteImageUrl,
    required this.localImagePath,
  });

  /// 로컬 PK(`book_reflection.id`).
  final int reflectionId;
  final String remoteImageUrl;

  /// `reflection_images/<파일명>` 상대 경로.
  final String localImagePath;
}
