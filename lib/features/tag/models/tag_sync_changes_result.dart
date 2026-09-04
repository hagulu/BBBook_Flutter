import '../../record_sync/models/record_sync_payload.dart';

/// `GET /api/me/tags/sync/changes` 응답. 태그/책-태그 매핑 증분 동기화 결과.
///
/// `ServerTag`/`ServerTagMap`은 `/api/me/records`(전체 조회)의 tags/tagMaps와
/// 스키마가 같아(api-doc 기준) record_sync 모듈의 정의를 그대로 재사용한다
/// (`BookNoteSyncChangesResult`와 같은 방식).
class TagSyncChangesResult {
  const TagSyncChangesResult({
    required this.upsertedTags,
    required this.deletedTagIds,
    required this.upsertedTagMaps,
    required this.deletedTagMapIds,
    required this.syncedAt,
    required this.fullSyncRequired,
  });

  final List<ServerTag> upsertedTags;
  final List<int> deletedTagIds;
  final List<ServerTagMap> upsertedTagMaps;
  final List<int> deletedTagMapIds;

  /// 이번 조회 기준 서버 시각. 다음 증분 동기화 요청 시 since 값으로 사용한다.
  final DateTime syncedAt;

  /// true면 삭제 이력(30일 보관 기간 초과 등)이 유실되었을 수 있어
  /// `GET /api/me/records`로 전체 동기화를 다시 수행해야 한다.
  final bool fullSyncRequired;

  factory TagSyncChangesResult.fromJson(Map<String, dynamic> json) {
    return TagSyncChangesResult(
      upsertedTags: (json['upsertedTags'] as List<dynamic>)
          .map((e) => ServerTag.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      deletedTagIds: (json['deletedTagIds'] as List<dynamic>)
          .map((e) => e as int)
          .toList(growable: false),
      upsertedTagMaps: (json['upsertedTagMaps'] as List<dynamic>)
          .map((e) => ServerTagMap.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      deletedTagMapIds: (json['deletedTagMapIds'] as List<dynamic>)
          .map((e) => e as int)
          .toList(growable: false),
      syncedAt: DateTime.parse(json['syncedAt'] as String),
      fullSyncRequired: json['fullSyncRequired'] as bool,
    );
  }
}
