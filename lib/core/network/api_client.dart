import 'dart:async';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'api_base_options.dart';
import 'api_exception.dart';

typedef AccessTokenReader = String? Function();
typedef AccessTokenRefresher = Future<String?> Function();
typedef UnauthorizedHandler = Future<void> Function();
typedef SanctionedHandler = Future<void> Function();

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
  SanctionedHandler? _onSanctioned;
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
    SanctionedHandler? onSanctioned,
    Future<void> Function()? prepareSession,
    void Function()? onUserRetry,
  }) {
    _readAccessToken = readAccessToken;
    _refreshAccessToken = refreshAccessToken;
    _onUnauthorized = onUnauthorized;
    _onSanctioned = onSanctioned;
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

  /// 인증과 전혀 무관한 조회(응답이 사용자에 따라 달라지지 않는다).
  /// 토큰을 붙이지 않는다 — 만료된 토큰 때문에 로그아웃 사용자의 조회가
  /// 401로 막히지 않게 하기 위함이다.
  static final _anonymousGetPaths = <RegExp>[
    RegExp(r'^/api/books/categories$'),
    // 정적 상수 기반 플랫폼 목록이라 사용자와 무관하다(api-books-options-get.md).
    RegExp(r'^/api/books/options$'),
    RegExp(r'^/api/notices(?:/\d+)?$'),
  ];

  /// 인증이 선택인 공개 조회(api-doc의 `Authorization ... (선택)` 엔드포인트).
  ///
  /// 비로그인 사용자도 그대로 조회할 수 있고, 토큰이 있으면 함께 보내
  /// `isMine`/`likedByMe`가 내 기준으로 채워진다. 응답이 사용자와 무관한
  /// `categories`/`options`는 [_anonymousGetPaths]가 맡으므로 여기서 뺀다
  /// (두 목록은 서로 겹치지 않게 유지한다).
  static final _authOptionalGetPaths = <RegExp>[
    RegExp(r'^/api/books$'),
    RegExp(r'^/api/books/(?!categories$|options$)[^/]+$'),
    RegExp(
      r'^/api/books/[^/]+/(?:reviews|reflections|discussions'
      r'|community-preview|community-counts)$',
    ),
    RegExp(r'^/api/discussions/\d+(?:/answers)?$'),
    RegExp(r'^/api/reflections/\d+$'),
    // 비로그인도 조회 가능하고, 공개 여부는 대상 사용자 설정만으로 결정된다
    // (api-users-id-books-finished-get.md).
    RegExp(r'^/api/users/\d+/books/finished$'),
  ];

  bool _isAnonymous(RequestOptions options) =>
      options.method == 'GET' &&
      _anonymousGetPaths.any((path) => path.hasMatch(options.path));

  bool _isAuthOptional(RequestOptions options) =>
      options.method == 'GET' &&
      _authOptionalGetPaths.any((path) => path.hasMatch(options.path));

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
      final anonymous = _isAnonymous(options);
      // 세션 준비에 성공했을 때만 토큰을 싣는다. 실패를 무시하고 그때의
      // [_readAccessToken] 값을 그대로 붙이면, 로그아웃이 시작돼
      // ([AuthNotifier.logout]이 상태를 비우기 전) 아직 남아 있는 이전 계정
      // 토큰이 공개 조회에 실려 `isMine`/`likedByMe`가 이전 계정 기준으로
      // 내려올 수 있다.
      var sessionReady = true;
      if (!anonymous) {
        if (_isAuthOptional(options)) {
          // 비로그인 사용자도 볼 수 있는 조회다. 세션을 준비하지 못했다고
          // (계정이 없거나 로그인 상태가 바뀌는 중이라고) 공개 콘텐츠까지
          // 막지는 않고, 대신 익명 요청으로 보낸다.
          try {
            await _prepareSession?.call();
          } catch (_) {
            sessionReady = false;
          }
        } else {
          await _prepareSession?.call();
        }
      }
      if (options.extra['requiresRecordSync'] == true) {
        await _waitForRecordSync();
      }
      if (generation != _sessionGeneration) throw _sessionChanged(options);
      final token = _readAccessToken?.call();
      if (token != null && !anonymous && sessionReady) {
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
    final body = error.response?.data;
    if (error.response?.statusCode == 403 &&
        body is Map &&
        body['errorCode'] == 'USER_SANCTIONED' &&
        error.requestOptions.path != '/api/users/me') {
      final refresh = _onSanctioned;
      if (refresh != null) unawaited(refresh());
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
