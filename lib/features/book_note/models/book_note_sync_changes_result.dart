import '../../record_sync/models/record_sync_payload.dart';

/// `GET /api/me/notes/sync/changes` 응답. 노트/메모 증분 동기화 결과.
///
/// `ServerBookNote`/`ServerBookNoteMemo`는 `/api/me/records`(전체 조회)의
/// notes/noteMemos와 스키마가 같아(api-doc 기준) record_sync 모듈의 정의를
/// 그대로 재사용한다.
class BookNoteSyncChangesResult {
  const BookNoteSyncChangesResult({
    required this.upsertedNotes,
    required this.deletedNoteIds,
    required this.upsertedNoteMemos,
    required this.deletedNoteMemoIds,
    required this.syncedAt,
    required this.fullSyncRequired,
  });

  final List<ServerBookNote> upsertedNotes;
  final List<int> deletedNoteIds;
  final List<ServerBookNoteMemo> upsertedNoteMemos;
  final List<int> deletedNoteMemoIds;

  /// 이번 조회 기준 서버 시각. 다음 증분 동기화 요청 시 since 값으로 사용한다.
  final DateTime syncedAt;

  /// true면 삭제 이력(30일 보관 기간 초과 등)이 유실되었을 수 있어
  /// `GET /api/me/records`로 전체 동기화를 다시 수행해야 한다.
  final bool fullSyncRequired;

  factory BookNoteSyncChangesResult.fromJson(Map<String, dynamic> json) {
    return BookNoteSyncChangesResult(
      upsertedNotes: (json['upsertedNotes'] as List<dynamic>)
          .map((e) => ServerBookNote.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      deletedNoteIds: (json['deletedNoteIds'] as List<dynamic>)
          .map((e) => e as int)
          .toList(growable: false),
      upsertedNoteMemos: (json['upsertedNoteMemos'] as List<dynamic>)
          .map((e) => ServerBookNoteMemo.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      deletedNoteMemoIds: (json['deletedNoteMemoIds'] as List<dynamic>)
          .map((e) => e as int)
          .toList(growable: false),
      syncedAt: DateTime.parse(json['syncedAt'] as String),
      fullSyncRequired: json['fullSyncRequired'] as bool,
    );
  }
}
