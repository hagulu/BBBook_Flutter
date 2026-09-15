import '../models/auth_user.dart';
import '../models/standalone_session.dart';

enum AuthStatus {
  authLoading,
  authenticated,
  localOnly,
  unauthenticated,

  /// 로그인하지 않고 이 기기에서만 기록을 남기는 상태("로그인 없이 사용하기").
  /// 서버 계정이 없으므로 개인 기록은 항상 로컬 저장 모드로만 두고, 서버는
  /// 인증이 필요 없는 공개 콘텐츠 조회에만 쓴다.
  standalone,
}

/// 앱 전역 인증 상태.
///
/// 원본(Next.js)의 `AuthProvider`(`isLoggedIn`, `isAuthLoading`, `user`,
/// `accessToken`)에 대응한다.
class AuthState {
  const AuthState({
    this.status = AuthStatus.authLoading,
    this.user,
    this.accessToken,
    this.requiresLogin = false,
  });

  final AuthStatus status;
  final AuthUser? user;
  final String? accessToken;
  final bool requiresLogin;

  bool get isAuthLoading => status == AuthStatus.authLoading;
  bool get isLoggedIn => status == AuthStatus.authenticated;

  /// 계정 없이 이 기기에서만 사용하는 상태인지.
  bool get isStandalone => status == AuthStatus.standalone;

  bool get canUseApp =>
      isLoggedIn || status == AuthStatus.localOnly || isStandalone;

  /// 로컬 개인 기록(노트·독후감)의 소유자 id. 계정이 없는 사용자는 고정
  /// sentinel([standaloneOwnerUserId])을 쓴다 — 화면마다 로그인 여부를 다시
  /// 검사하지 않도록 기록 계열 provider는 항상 이 값만 본다.
  int? get recordOwnerId => isStandalone ? standaloneOwnerUserId : user?.id;
}
