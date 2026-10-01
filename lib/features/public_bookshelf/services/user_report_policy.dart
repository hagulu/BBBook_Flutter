/// 사용자 신고 노출 조건. 로그인한 계정이 있고 본인이 아닌 사용자만 신고할 수 있다.
bool canReportUser({
  required bool isLoggedIn,
  required int? myUserId,
  required int targetUserId,
}) {
  return isLoggedIn && myUserId != targetUserId;
}
