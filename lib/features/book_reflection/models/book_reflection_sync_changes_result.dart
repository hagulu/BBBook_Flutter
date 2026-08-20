import '../../record_sync/models/record_sync_payload.dart';

/// `GET /api/me/reflections/sync/changes` 응답. 독후감 증분 동기화 결과.
///
/// `ServerBookReflection`은 `/api/me/records`(전체 조회)의 reflections와
/// 스키마가 같아(api-doc 기준) record_sync 모듈의 정의를 그대로 재사용한다.
class BookReflectionSyncChangesResult {
  const BookReflectionSyncChangesResult({
    required this.upsertedReflections,
    required this.deletedReflectionIds,
    required this.syncedAt,
    required this.fullSyncRequired,
  });

  final List<ServerBookReflection> upsertedReflections;
  final List<int> deletedReflectionIds;

  /// 이번 조회 기준 서버 시각. 다음 증분 동기화 요청 시 since 값으로 사용한다.
  final DateTime syncedAt;

  /// true면 삭제 이력(30일 보관 기간 초과 등)이 유실되었을 수 있어
  /// `GET /api/me/records`로 전체 동기화를 다시 수행해야 한다.
  final bool fullSyncRequired;

  factory BookReflectionSyncChangesResult.fromJson(Map<String, dynamic> json) {
    return BookReflectionSyncChangesResult(
      upsertedReflections: (json['upserted'] as List<dynamic>)
          .map((e) => ServerBookReflection.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      deletedReflectionIds: (json['deletedReflectionIds'] as List<dynamic>)
          .map((e) => e as int)
          .toList(growable: false),
      syncedAt: DateTime.parse(json['syncedAt'] as String),
      fullSyncRequired: json['fullSyncRequired'] as bool,
    );
  }
}
