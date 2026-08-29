/// 토론 화면의 날짜 표기. 서버가 내려주는 UTC ISO8601 값을 기기 로컬 시각으로
/// 바꿔 보여준다.
library;

/// `2026.08.27` — 목록 카드/마감일 표기.
String formatDiscussionDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}.$month.$day';
}

/// 상세/답변 카드의 작성 시각. 화면을 오래 열어 둬도 표시가 오래된 상대
/// 시각으로 남지 않도록 `2026.08.27 16:47` 형태의 절대 시각을 사용한다.
String formatDiscussionDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${formatDiscussionDate(value)} $hour:$minute';
}
