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

/// `2026.08.27 16:47` — 절대 날짜/시각.
String _formatDiscussionAbsoluteDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${formatDiscussionDate(value)} $hour:$minute';
}

/// 상세/답변 카드의 작성 시각. 30일(약 한 달) 미만이면 상대 표기(초/분/시간/일
/// 전), 그 이상이면 `2026.08.27 16:47`처럼 절대 날짜/시각으로 보여준다.
String formatDiscussionDateTime(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inDays >= 30) return _formatDiscussionAbsoluteDateTime(value);
  if (diff.inDays >= 1) return '${diff.inDays}일 전';
  if (diff.inHours >= 1) return '${diff.inHours}시간 전';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}분 전';
  return '${diff.inSeconds < 0 ? 0 : diff.inSeconds}초 전';
}
