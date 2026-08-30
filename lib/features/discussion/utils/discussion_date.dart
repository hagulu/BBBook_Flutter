/// 토론 화면의 날짜 표기. 서버가 내려주는 UTC ISO8601 값을 기기 로컬 시각으로
/// 바꿔 보여준다.
library;

import '../../../core/utils/relative_time.dart';

/// `2026.08.27` — 목록 카드/마감일 표기.
String formatDiscussionDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}.$month.$day';
}

/// `2026.08.27 16:47` — 마감일 등 날짜+시간이 필요한 절대 시각 표기.
String formatDiscussionDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${formatDiscussionDate(value)} $hour:$minute';
}

/// 작성 시각의 상대 표기(`N초 전`/`N분 전`/`N시간 전`/`N일 전`). 30일이
/// 지났거나 미래 시각(시계 오차)이면 [formatDiscussionDate]의 절대 표기로
/// 되돌린다.
String formatRelativeDiscussionDate(DateTime value) =>
    formatRelativeTime(value, fallback: formatDiscussionDate);

/// 작성 시각의 상대 표기. 30일이 지났거나 미래 시각이면
/// [formatDiscussionDateTime]의 절대(날짜+시간) 표기로 되돌린다.
String formatRelativeDiscussionDateTime(DateTime value) =>
    formatRelativeTime(value, fallback: formatDiscussionDateTime);
