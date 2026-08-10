import '../models/auth_user.dart';

enum AuthStatus { authLoading, authenticated, unauthenticated }

/// 앱 전역 인증 상태.
///
/// 원본(Next.js)의 `AuthProvider`(`isLoggedIn`, `isAuthLoading`, `user`,
/// `accessToken`)에 대응한다.
class AuthState {
  const AuthState({
    this.status = AuthStatus.authLoading,
    this.user,
    this.accessToken,
  });

  final AuthStatus status;
  final AuthUser? user;
  final String? accessToken;

  bool get isAuthLoading => status == AuthStatus.authLoading;
  bool get isLoggedIn => status == AuthStatus.authenticated;
}
