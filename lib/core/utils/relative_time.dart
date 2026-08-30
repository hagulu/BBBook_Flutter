/// 작성 시각처럼 과거 시각을 사람이 읽기 쉬운 상대 표기로 바꾸는 공용 유틸.
library;

/// [value]가 30일 이내면 `N초 전`/`N분 전`/`N시간 전`/`N일 전`로, 그 이상
/// 지났거나 미래 시각(시계 오차)이면 [fallback]이 만든 절대 표기를 그대로
/// 쓴다.
String formatRelativeTime(
  DateTime value, {
  required String Function(DateTime value) fallback,
}) {
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.isNegative || diff.inDays >= 30) return fallback(value);
  if (diff.inDays >= 1) return '${diff.inDays}일 전';
  if (diff.inHours >= 1) return '${diff.inHours}시간 전';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}분 전';
  if (diff.inSeconds >= 1) return '${diff.inSeconds}초 전';
  return '방금 전';
}
