import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'api_base_options.dart';

typedef AccessTokenReader = String? Function();
typedef AccessTokenRefresher = Future<String?> Function();
typedef UnauthorizedHandler = Future<void> Function();

/// 인증이 필요한 API 요청 전용 공통 클라이언트.
///
/// 요청 시 저장된 accessToken을 헤더에 실어 보내고, 401 응답을 받으면
/// [AccessTokenRefresher]로 1회 재시도한다. 재시도도 실패하면
/// [UnauthorizedHandler](로그아웃 처리)를 호출한다.
/// (CLAUDE.md 인증 API 호출 규칙 / features/auth.md 401 처리 규칙)
class ApiClient {
  ApiClient({String baseUrl = ApiConfig.baseUrl})
    : dio = Dio(buildApiBaseOptions(baseUrl: baseUrl)) {
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  final Dio dio;

  AccessTokenReader? _readAccessToken;
  AccessTokenRefresher? _refreshAccessToken;
  UnauthorizedHandler? _onUnauthorized;

  Future<String?>? _refreshing;
  Future<void>? _handlingUnauthorized;

  /// AuthProvider에서 토큰 조회/갱신/로그아웃 처리를 주입한다.
  void configureAuth({
    required AccessTokenReader readAccessToken,
    required AccessTokenRefresher refreshAccessToken,
    required UnauthorizedHandler onUnauthorized,
  }) {
    _readAccessToken = readAccessToken;
    _refreshAccessToken = refreshAccessToken;
    _onUnauthorized = onUnauthorized;
  }

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _readAccessToken?.call();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final refresher = _refreshAccessToken;
    final isUnauthorized = error.response?.statusCode == 401;
    final alreadyRetried = error.requestOptions.extra['retried'] == true;

    if (!isUnauthorized || refresher == null) {
      handler.next(error);
      return;
    }

    if (alreadyRetried) {
      // refresh로 재발급한 토큰으로 재시도한 요청까지 401이면 세션이 완전히
      // 무효화된 것으로 보고 로그아웃 처리한다.
      await _notifyUnauthorizedOnce();
      handler.next(error);
      return;
    }

    String? newToken;
    try {
      newToken = await _refreshTokenOnce(refresher);
    } catch (_) {
      // refresh 시도 자체가 일시적으로 실패(네트워크/서버 오류 등)한 경우다.
      // 세션이 아직 유효할 수 있으므로 로그아웃하지 않고 원래 오류만 전달한다.
      handler.next(error);
      return;
    }

    if (newToken == null) {
      // 저장된 refresh token이 없거나 실제로 만료/거부된 경우에만 여기 도달한다.
      await _notifyUnauthorizedOnce();
      handler.next(error);
      return;
    }

    try {
      final retryOptions = error.requestOptions
        ..headers['Authorization'] = 'Bearer $newToken'
        ..extra['retried'] = true;
      final response = await dio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// 동시에 여러 요청이 401을 받아도 refresh 호출은 한 번만 나가도록 묶는다.
  Future<String?> _refreshTokenOnce(AccessTokenRefresher refresher) {
    return _refreshing ??= refresher().whenComplete(() => _refreshing = null);
  }

  /// 동시에 여러 요청이 로그아웃 대상으로 판정돼도 [UnauthorizedHandler]는
  /// 한 번만 실행되도록 묶는다.
  Future<void> _notifyUnauthorizedOnce() {
    final handler = _onUnauthorized;
    if (handler == null) return Future<void>.value();
    return _handlingUnauthorized ??= handler().whenComplete(
      () => _handlingUnauthorized = null,
    );
  }
}
