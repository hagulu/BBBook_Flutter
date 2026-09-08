import 'dart:async';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'api_base_options.dart';
import 'api_exception.dart';

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
  ApiClient({
    String baseUrl = ApiConfig.baseUrl,
    DateTime Function()? now,
    this.recordSyncWait = const Duration(seconds: 3),
  }) : _now = now ?? DateTime.now,
       dio = Dio(buildApiBaseOptions(baseUrl: baseUrl)) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onResponse: _onResponse,
        onError: _onError,
      ),
    );
  }

  final Dio dio;
  final DateTime Function() _now;
  final Duration recordSyncWait;

  AccessTokenReader? _readAccessToken;
  AccessTokenRefresher? _refreshAccessToken;
  UnauthorizedHandler? _onUnauthorized;
  Future<void> Function()? _prepareSession;
  void Function()? _onUserRetry;
  void Function()? onNetworkAvailable;
  Future<void> Function()? prepareRecordSync;
  int _sessionGeneration = 0;
  DateTime? _retryAfter;

  Future<String?>? _refreshing;
  Future<void>? _handlingUnauthorized;

  /// AuthProvider에서 토큰 조회/갱신/로그아웃 처리를 주입한다.
  void configureAuth({
    required AccessTokenReader readAccessToken,
    required AccessTokenRefresher refreshAccessToken,
    required UnauthorizedHandler onUnauthorized,
    Future<void> Function()? prepareSession,
    void Function()? onUserRetry,
  }) {
    _readAccessToken = readAccessToken;
    _refreshAccessToken = refreshAccessToken;
    _onUnauthorized = onUnauthorized;
    _prepareSession = prepareSession;
    _onUserRetry = onUserRetry;
  }

  /// 사용자가 명시적으로 재시도했을 때만 일시 오류 대기를 해제한다.
  /// 인증 무효나 진행 중인 요청은 변경하지 않는다.
  void requestUserRetry() {
    _retryAfter = null;
    _onUserRetry?.call();
  }

  Future<void> _waitForRecordSync() async {
    await prepareRecordSync?.call().timeout(recordSyncWait, onTimeout: () {});
  }

  /// 진행 중인 이전 세션의 요청/응답을 새 계정에서 재사용하지 않는다.
  void invalidateSession() {
    _sessionGeneration++;
    _retryAfter = null;
  }

  bool _isPublic(RequestOptions options) =>
      options.method == 'GET' && options.path == '/api/books/categories';

  /// 로컬 기록에 의존하는 온라인 작업만 명시적으로 사용한다.
  /// 동기화 자체의 API에는 붙이지 않아 재귀 대기를 피한다.
  static Options recordDependentOptions() =>
      Options(extra: const {'requiresRecordSync': true});

  /// 책별 직렬 큐를 사용하는 작업은 큐에 들어가기 전에 호출해야 한다.
  Future<void> prepareRecordOperation() async {
    final generation = _sessionGeneration;
    await _prepareSession?.call();
    await _waitForRecordSync();
    if (generation != _sessionGeneration) {
      throw const ApiException('로그인 상태가 변경되었습니다.');
    }
  }

  DioException _sessionChanged(RequestOptions options) => DioException(
    requestOptions: options,
    type: DioExceptionType.cancel,
    error: const ApiException('로그인 상태가 변경되었습니다.'),
  );

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final generation = options.extra.putIfAbsent(
      'authGeneration',
      () => _sessionGeneration,
    );
    try {
      if (generation != _sessionGeneration) throw _sessionChanged(options);
      if (_retryAfter case final retryAfter? when _now().isBefore(retryAfter)) {
        throw const ApiException('네트워크 연결 후 다시 시도해 주세요.');
      }
      if (!_isPublic(options)) await _prepareSession?.call();
      if (options.extra['requiresRecordSync'] == true) {
        await _waitForRecordSync();
      }
      if (generation != _sessionGeneration) throw _sessionChanged(options);
      final token = _readAccessToken?.call();
      if (token != null && !_isPublic(options)) {
        options.headers['Authorization'] = 'Bearer $token';
      } else {
        options.headers.remove('Authorization');
      }
      handler.next(options);
    } catch (e) {
      handler.reject(
        e is DioException ? e : DioException(requestOptions: options, error: e),
      );
    }
  }

  void _onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (response.requestOptions.extra['authGeneration'] != _sessionGeneration) {
      handler.reject(_sessionChanged(response.requestOptions));
      return;
    }
    _retryAfter = null;
    onNetworkAvailable?.call();
    handler.next(response);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (error.requestOptions.extra['authGeneration'] != _sessionGeneration) {
      handler.next(_sessionChanged(error.requestOptions));
      return;
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        (error.response?.statusCode ?? 0) >= 500) {
      _retryAfter = _now().add(const Duration(seconds: 15));
    }
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
      await _rejectUnauthorized(error, handler);
      return;
    }

    String? newToken;
    try {
      final currentToken = _readAccessToken?.call();
      final sentToken = error.requestOptions.headers['Authorization'];
      newToken = currentToken != null && sentToken != 'Bearer $currentToken'
          ? currentToken
          : await _refreshTokenOnce(refresher);
    } catch (e) {
      // refresh 시도 자체가 일시적으로 실패(네트워크/서버 오류 등)한 경우다.
      // 세션이 아직 유효할 수 있으므로 로그아웃하지 않고 원래 오류만 전달한다.
      // 일시적인 갱신 실패를 원래 401로 포장하면 호출부가 로그아웃으로
      // 오인한다. 실제 갱신 실패를 인증 실패와 구분해서 전달한다.
      handler.next(
        DioException(requestOptions: error.requestOptions, error: e),
      );
      return;
    }

    if (newToken == null) {
      // 저장된 refresh token이 없거나 실제로 만료/거부된 경우에만 여기 도달한다.
      await _rejectUnauthorized(error, handler);
      return;
    }

    try {
      final retryOptions = error.requestOptions
        ..headers['Authorization'] = 'Bearer $newToken'
        ..extra['retried'] = true;
      if (retryOptions.data case final FormData data) {
        retryOptions.data = data.clone();
      }
      final response = await dio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (e) {
      handler.next(
        DioException(requestOptions: error.requestOptions, error: e),
      );
    }
  }

  Future<void> _rejectUnauthorized(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      await _notifyUnauthorizedOnce();
    } catch (_) {
      // 정리 작업의 실패 때문에 요청 Future가 끝나지 않는 것을 막는다.
    } finally {
      handler.next(error);
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
