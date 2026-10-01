import 'package:dio/dio.dart';

/// API 요청 실패 시 화면에 노출할 메시지를 담는 예외.
///
/// 내부 원인(cause)은 로그에만 남기고, [message]는 사용자에게 보여줄 짧은 문구로 유지한다.
class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.errorCode,
    this.cause,
  });

  final String message;
  final int? statusCode;

  /// 서버가 내려준 ErrorCode enum 이름(예: `NOTE_IMAGE_LIMIT_EXCEEDED`).
  /// 특정 비즈니스 오류를 구분해서 처리해야 할 때만 쓰고, 그 외에는
  /// [message]만 그대로 보여준다.
  final String? errorCode;
  final Object? cause;

  static ApiException? sanctionedFromDio(DioException error) {
    final data = error.response?.data;
    if (error.response?.statusCode != 403 ||
        data is! Map ||
        data['errorCode'] != 'USER_SANCTIONED') {
      return null;
    }
    return ApiException(
      '징계 기간에는 이 기능을 사용할 수 없습니다. 마이 화면에서 자세한 내용을 확인해 주세요.',
      statusCode: 403,
      errorCode: 'USER_SANCTIONED',
      cause: error,
    );
  }

  /// 403 USER_SANCTIONED는 인증 무효가 아니므로 로그아웃 대상으로 보지 않는다.
  bool get isAuthFailure =>
      statusCode == 401 ||
      (statusCode == 403 && errorCode != 'USER_SANCTIONED');

  @override
  String toString() =>
      'ApiException(statusCode: $statusCode, message: $message)';
}
