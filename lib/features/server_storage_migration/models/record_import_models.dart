/// 로컬 → 서버 저장 모드 재전환 Import 세션(`/api/me/records/import/*`)의
/// 요청/응답 값 객체.
///
/// 문서: ../../../../../api-doc/api-me-records-import-start-post.md,
/// api-me-records-import-importId-items-post.md,
/// api-me-records-import-importId-attachments-post.md,
/// api-me-records-import-importId-complete-post.md,
/// api-me-records-import-importId-cancel-post.md
library;

/// `/start` 응답.
class RecordImportSession {
  const RecordImportSession({
    required this.importId,
    required this.status,
    required this.importedCount,
    required this.maxChunkItemCount,
    required this.createdAt,
  });

  final int importId;
  final String status;
  final int importedCount;
  final int maxChunkItemCount;
  final DateTime createdAt;

  factory RecordImportSession.fromJson(Map<String, dynamic> json) {
    return RecordImportSession(
      importId: json['importId'] as int,
      status: json['status'] as String,
      importedCount: json['importedCount'] as int,
      maxChunkItemCount: json['maxChunkItemCount'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// `/items` 응답의 6개 배열이 공통으로 갖는 항목 하나(`localId`/`serverId`/`created`).
class RecordImportEntityResult {
  const RecordImportEntityResult({
    required this.localId,
    required this.serverId,
    required this.created,
  });

  final int localId;
  final int serverId;
  final bool created;

  factory RecordImportEntityResult.fromJson(Map<String, dynamic> json) {
    return RecordImportEntityResult(
      localId: json['localId'] as int,
      serverId: json['serverId'] as int,
      created: json['created'] as bool,
    );
  }
}

/// `/items` 청크 한 번의 응답.
class RecordImportChunkResult {
  const RecordImportChunkResult({
    required this.books,
    required this.notes,
    required this.noteMemos,
    required this.reflections,
    required this.tags,
    required this.tagMaps,
    required this.importedCount,
  });

  final List<RecordImportEntityResult> books;
  final List<RecordImportEntityResult> notes;
  final List<RecordImportEntityResult> noteMemos;
  final List<RecordImportEntityResult> reflections;
  final List<RecordImportEntityResult> tags;
  final List<RecordImportEntityResult> tagMaps;

  /// 이 청크 하나가 아니라 세션 전체 누적 저장 건수(참고용, 검증에는 쓰지
  /// 않는다 — `/complete`의 건수 정합성은 클라이언트가 보낸 로컬 배열
  /// 길이로 직접 계산한다).
  final int importedCount;

  factory RecordImportChunkResult.fromJson(Map<String, dynamic> json) {
    List<RecordImportEntityResult> parse(String key) {
      return (json[key] as List<dynamic>? ?? const [])
          .map(
            (e) => RecordImportEntityResult.fromJson(e as Map<String, dynamic>),
          )
          .toList(growable: false);
    }

    return RecordImportChunkResult(
      books: parse('books'),
      notes: parse('notes'),
      noteMemos: parse('noteMemos'),
      reflections: parse('reflections'),
      tags: parse('tags'),
      tagMaps: parse('tagMaps'),
      importedCount: json['importedCount'] as int,
    );
  }
}

/// `/attachments` 대상 종류.
enum RecordImportAttachmentEntityType {
  noteMemo('NOTE_MEMO'),
  reflection('REFLECTION');

  const RecordImportAttachmentEntityType(this.apiValue);

  final String apiValue;
}

/// `/attachments` 응답.
class RecordImportAttachmentResult {
  const RecordImportAttachmentResult({
    required this.localId,
    required this.serverId,
    required this.imageUrl,
  });

  final int localId;
  final int serverId;
  final String imageUrl;

  factory RecordImportAttachmentResult.fromJson(Map<String, dynamic> json) {
    return RecordImportAttachmentResult(
      localId: json['localId'] as int,
      serverId: json['serverId'] as int,
      imageUrl: json['imageUrl'] as String,
    );
  }
}

/// `/complete` 요청 body(건수 정합성 검증 기준).
class RecordImportCounts {
  const RecordImportCounts({
    required this.bookCount,
    required this.noteCount,
    required this.noteMemoCount,
    required this.reflectionCount,
    required this.tagCount,
    required this.tagMapCount,
  });

  final int bookCount;
  final int noteCount;
  final int noteMemoCount;
  final int reflectionCount;
  final int tagCount;
  final int tagMapCount;

  Map<String, dynamic> toJson() => {
    'bookCount': bookCount,
    'noteCount': noteCount,
    'noteMemoCount': noteMemoCount,
    'reflectionCount': reflectionCount,
    'tagCount': tagCount,
    'tagMapCount': tagMapCount,
  };
}

/// 요청이 서버 Import 처리에 도달하기 전이든 후든, 실패했다는 사실 자체가
/// "이 importId는 더 이상 못 쓴다"는 서로 다른 의미를 갖는 상태 코드들을
/// [ServerStorageMigrationService]가 구분해 다룰 수 있도록 분류한다
/// (문서 "실패 시 동작" — 대부분의 실패는 서버가 세션 전체를 이미 정리한다).
enum RecordImportFailureKind {
  /// 404 — 세션이 없거나 본인 소유가 아님(정리 대상 아님).
  sessionNotFound,

  /// 409 — 세션이 이미 COMPLETED(정리 대상 아님).
  sessionCompleted,

  /// 410 — 세션이 EXPIRED(서버가 세션 전체를 정리했거나 정리 트랜잭션 자체가
  /// 실패해 남은 상태 — 어느 쪽이든 이 importId는 재사용 불가).
  sessionExpired,

  /// 400/500 — 요청·검증 실패(문서 기준 이 경우도 세션 전체가 정리된다).
  requestFailed,

  /// 응답을 받지 못함(네트워크 오류·타임아웃 등).
  network,

  unknown,
}

class RecordImportException implements Exception {
  const RecordImportException(
    this.message, {
    required this.kind,
    this.statusCode,
    this.cause,
  });

  final String message;
  final RecordImportFailureKind kind;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() =>
      'RecordImportException(kind: $kind, statusCode: $statusCode, message: $message)';
}
