import '../models/notice_summary.dart';

/// 새 공지 배지 판단(순수 함수).
///
/// 서버는 7일 이내 최신 일반 공지 id만 주고(`/api/notices/latest`), 확인 여부는
/// 앱이 마지막으로 확인한 공지 id와 비교해 판단한다.
class NoticeBadgeService {
  const NoticeBadgeService._();

  /// 최신 공지가 있고, 마지막으로 확인한 id보다 새로우면 true.
  /// 확인 기록이 없으면 최신 공지가 있을 때 true.
  static bool hasNewNotice({int? latestId, int? lastSeenId}) {
    if (latestId == null) return false;
    if (lastSeenId == null) return true;
    return latestId > lastSeenId;
  }

  /// 목록 진입 시 저장할 확인 id. 기존 값보다 과거로 되돌리지 않으며,
  /// 저장할 값이 없으면 null.
  static int? nextLastSeenId({int? latestId, int? lastSeenId}) {
    if (latestId == null) return null;
    if (lastSeenId != null && latestId <= lastSeenId) return null;
    return latestId;
  }

  /// 화면에 표시한 목록에 포함된 일반 공지 중 가장 큰 id. 없으면 null.
  /// 목록 조회 이후에 등록된 공지는 포함하지 않으므로, 보여 주지 않은 공지가
  /// 확인 처리되지 않는다.
  static int? latestNormalId(List<NoticeSummary> items) {
    int? latest;
    for (final item in items) {
      if (item.isImportant) continue;
      if (latest == null || item.id > latest) latest = item.id;
    }
    return latest;
  }
}
