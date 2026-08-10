import 'book_item.dart';

/// `GET /api/me/books/sync/changes` 응답. 증분 동기화 결과.
class SyncChangesResult {
  const SyncChangesResult({
    required this.upserted,
    required this.deletedUserBookIds,
    required this.syncedAt,
    required this.fullSyncRequired,
  });

  final List<BookItem> upserted;
  final List<int> deletedUserBookIds;

  /// 이번 조회 기준 서버 시각. 다음 증분 동기화 요청 시 since 값으로 사용한다.
  final DateTime syncedAt;

  /// true면 삭제 이력이 유실되었을 수 있어 전체 동기화로 대체해야 한다.
  final bool fullSyncRequired;

  factory SyncChangesResult.fromJson(Map<String, dynamic> json) {
    return SyncChangesResult(
      upserted: (json['upserted'] as List<dynamic>)
          .map((e) => BookItem.fromSyncJson(e as Map<String, dynamic>))
          .toList(),
      deletedUserBookIds: (json['deletedUserBookIds'] as List<dynamic>)
          .map((e) => e as int)
          .toList(),
      syncedAt: DateTime.parse(json['syncedAt'] as String),
      fullSyncRequired: json['fullSyncRequired'] as bool,
    );
  }
}
