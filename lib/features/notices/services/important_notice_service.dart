import '../models/notice_detail.dart';

/// 중요 공지 팝업 대상 선택(순수 함수).
///
/// 7일 이내 여부 등 기간 판단은 서버가 끝낸 응답을 그대로 신뢰한다.
class ImportantNoticeService {
  const ImportantNoticeService._();

  /// "그만 보기"한 공지를 제외한 팝업 대상 전체를 서버 정렬(최신 등록순) 그대로
  /// 반환한다. 팝업 하나 안에서 한 건씩 넘겨 보므로 연속 팝업은 뜨지 않는다.
  static List<NoticeDetail> pickPopupNotices(
    List<NoticeDetail> items,
    Set<int> dismissedIds,
  ) {
    return [
      for (final item in items)
        if (!dismissedIds.contains(item.id)) item,
    ];
  }
}
