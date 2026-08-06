import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../models/auth_user.dart';
import 'auth_api.dart';
import 'social_auth_service.dart';

class AuthSession {
  const AuthSession({required this.user, required this.accessToken});

  final AuthUser user;
  final String accessToken;
}

/// 인증 세션의 source of truth. [AuthApi], [SocialAuthService], [TokenStorage]
/// 조합과 토큰 회전/세션 정리를 이 안에서만 처리하고, AuthNotifier는 이 결과를
/// 받아 상태 전이만 담당한다.
class AuthRepository {
  AuthRepository({
    required AuthApi authApi,
    required TokenStorage tokenStorage,
    required SocialAuthService socialAuthService,
  }) : _authApi = authApi,
       _tokenStorage = tokenStorage,
       _socialAuthService = socialAuthService;

  final AuthApi _authApi;
  final TokenStorage _tokenStorage;
  final SocialAuthService _socialAuthService;

  Future<AuthSession> loginWithProvider(SocialProvider provider) async {
    final idToken = await _idTokenFor(provider);
    final result = await _authApi.postProviderLogin(provider: provider, idToken: idToken);
    await _tokenStorage.saveRefreshToken(result.tokens.refreshToken);
    return AuthSession(user: result.user, accessToken: result.tokens.accessToken);
  }

  Future<String> _idTokenFor(SocialProvider provider) {
    return switch (provider) {
      SocialProvider.google => _socialAuthService.signInWithGoogle(),
      SocialProvider.apple => _socialAuthService.signInWithApple(),
    };
  }

  /// 저장된 refreshToken으로 새 accessToken을 받아온다.
  ///
  /// 저장된 토큰이 없거나 인증이 실제로 무효화(401/403)된 경우 null을 반환하고
  /// 저장된 토큰도 지운다. 네트워크 오류/5xx 등 일시적인 실패는 토큰을 지우지
  /// 않고 [ApiException]을 그대로 던져 호출부가 구분해서 처리하게 한다.
  Future<String?> refreshAccessToken() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      return null;
    }

    try {
      final tokens = await _authApi.postRefresh(refreshToken: refreshToken);
      await _tokenStorage.saveRefreshToken(tokens.refreshToken);
      return tokens.accessToken;
    } on ApiException catch (e) {
      if (e.isAuthFailure) {
        await _tokenStorage.clearRefreshToken();
        return null;
      }
      rethrow;
    }
  }

  Future<AuthUser> fetchCurrentUser() => _authApi.getMe();

  /// 사용자가 직접 요청한 로그아웃. 서버 로그아웃이 실패해도 로컬 세션은 정리한다.
  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    try {
      await _authApi.postLogout(refreshToken: refreshToken);
    } on ApiException {
      // 서버 로그아웃 실패해도 클라이언트 상태는 초기화한다.
    }
    await clearLocalSession();
  }

  /// 401 재시도 실패 등으로 세션을 강제로 정리할 때 사용(서버 호출 없음).
  ///
  /// refresh token 삭제(우리 앱의 로그인 상태 판단 기준)가 핵심이므로, 소셜
  /// SDK 쪽 로그아웃이 실패해도 이 메서드는 실패하지 않는다.
  Future<void> clearLocalSession() async {
    await _tokenStorage.clearRefreshToken();
    try {
      await _socialAuthService.signOutGoogle();
    } catch (_) {
      // 다음 Google 로그인 시도에서 계정 선택 화면이 다시 뜨는 정도의 영향만 있다.
    }
  }
}
