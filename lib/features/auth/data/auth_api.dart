import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/client_id_storage.dart';
import '../models/auth_tokens.dart';
import '../models/auth_user.dart';

enum SocialProvider {
  google,
  apple;

  String get apiValue => name;
}

/// 인증 관련 API 호출(모바일 전용 엔드포인트).
///
/// 문서: ../../../../../api-doc/api-auth-mobile-provider-login-post.md,
/// api-auth-mobile-refresh-post.md, api-auth-mobile-logout-post.md, api-users-me.md
///
/// 로그인/refresh/logout은 Authorization 헤더 대상이나 401 재시도 대상이 아니므로
/// [ApiClient]의 인증 인터셉터를 거치지 않는 별도 [authDio]를 사용하고,
/// getMe만 [ApiClient]를 통해 요청한다.
class AuthApi {
  AuthApi({required Dio authDio, required ApiClient apiClient, required ClientIdStorage clientIdStorage})
    : _authDio = authDio,
      _apiClient = apiClient,
      _clientIdStorage = clientIdStorage;

  final Dio _authDio;
  final ApiClient _apiClient;
  final ClientIdStorage _clientIdStorage;

  /// POST /api/auth/mobile/{provider}/login
  Future<({AuthTokens tokens, AuthUser user})> postProviderLogin({
    required SocialProvider provider,
    required String idToken,
  }) async {
    try {
      final response = await _authDio.post<Map<String, dynamic>>(
        '/api/auth/mobile/${provider.apiValue}/login',
        data: {'token': idToken},
        options: Options(headers: await _clientIdHeader()),
      );
      final data = _unwrap(response);
      return (
        tokens: AuthTokens.fromJson(data),
        user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/auth/mobile/refresh
  Future<AuthTokens> postRefresh({required String refreshToken}) async {
    try {
      final response = await _authDio.post<Map<String, dynamic>>(
        '/api/auth/mobile/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(headers: await _clientIdHeader()),
      );
      return AuthTokens.fromJson(_unwrap(response));
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  /// POST /api/auth/mobile/logout
  Future<void> postLogout({String? refreshToken}) async {
    try {
      await _authDio.post<Map<String, dynamic>>(
        '/api/auth/mobile/logout',
        data: {'refreshToken': refreshToken},
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// GET /api/users/me
  Future<AuthUser> getMe() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>('/api/users/me');
      return AuthUser.fromJson(_unwrap(response));
    } on DioException catch (e) {
      throw _mapError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('서버 응답 형식이 올바르지 않습니다.', cause: e);
    }
  }

  Future<Map<String, dynamic>> _clientIdHeader() async {
    final clientId = await _clientIdStorage.getOrCreateClientId();
    return {'X-Client-Id': clientId};
  }

  Map<String, dynamic> _unwrap(Response<Map<String, dynamic>> response) {
    final body = response.data;
    if (body == null || body['data'] is! Map<String, dynamic>) {
      throw const ApiException('서버 응답을 처리할 수 없습니다.');
    }
    return body['data'] as Map<String, dynamic>;
  }

  ApiException _mapError(DioException e) {
    final statusCode = e.response?.statusCode;
    final message = switch (statusCode) {
      400 => '잘못된 요청입니다.',
      401 => '인증에 실패했습니다.',
      403 => '탈퇴한 계정입니다.',
      404 => '사용자 정보를 찾을 수 없습니다.',
      _ => '요청 처리 중 오류가 발생했습니다.',
    };
    return ApiException(message, statusCode: statusCode, cause: e);
  }
}
