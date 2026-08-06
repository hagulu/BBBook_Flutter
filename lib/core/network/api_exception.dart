/// API 요청 실패 시 화면에 노출할 메시지를 담는 예외.
///
/// 내부 원인(cause)은 로그에만 남기고, [message]는 사용자에게 보여줄 짧은 문구로 유지한다.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  /// 세션이 실제로 무효화된 경우(401/403)만 true. 그 외(네트워크 오류, 5xx,
  /// 응답 형식 오류 등)는 일시적인 실패로 보고 로그아웃 처리하지 않는다.
  bool get isAuthFailure => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'ApiException(statusCode: $statusCode, message: $message)';
}
