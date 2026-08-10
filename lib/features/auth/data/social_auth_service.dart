import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// 소셜 로그인 실패 시 화면에 노출할 메시지를 담는 예외.
class SocialAuthException implements Exception {
  const SocialAuthException(this.message);
  final String message;
}

/// Google/Apple 네이티브 SDK로 소셜 로그인을 수행해 id_token을 반환한다.
///
/// 원본(Next.js)은 브라우저 팝업 + postMessage 기반이었으나, 모바일에서는
/// 네이티브 Google/Apple Sign-In SDK로 완전히 대체한다(features/auth.md
/// Flutter 이관 시 주의사항).
class SocialAuthService {
  // 백엔드가 id_token의 audience를 검증하므로 값이 백엔드 설정과 일치해야 한다.
  static const _googleClientId =
      '585070787661-73kr7939i6slm4c1r53egdn2mi9c48si.apps.googleusercontent.com';
  static const _googleServerClientId =
      '585070787661-nm9rlng3ab2pccff926ot80and5pgolt.apps.googleusercontent.com';

  bool _googleInitialized = false;

  /// Android/Web에서 Apple 로그인을 쓰려면 Apple Service ID(clientId)와
  /// 백엔드가 처리할 redirectUri가 필요하다(placeholder로 대체 불가 — 실제
  /// 도메인/서비스 설정 필요). 값이 없는 동안은 iOS/macOS 네이티브 플로우만 지원한다.
  bool get isAppleSignInSupported =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Future<String> signInWithGoogle() async {
    try {
      if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize(
          clientId: _googleClientId,
          serverClientId: _googleServerClientId,
        );
        _googleInitialized = true;
      }

      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const SocialAuthException('Google 로그인에 실패했습니다.');
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const SocialAuthException('로그인이 취소되었습니다.');
      }
      throw const SocialAuthException('Google 로그인 중 오류가 발생했습니다.');
    }
  }

  Future<String> signInWithApple() async {
    if (!isAppleSignInSupported) {
      throw const SocialAuthException('현재 플랫폼에서는 Apple 로그인을 지원하지 않습니다.');
    }
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const SocialAuthException('Apple 로그인에 실패했습니다.');
      }
      return idToken;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const SocialAuthException('로그인이 취소되었습니다.');
      }
      throw const SocialAuthException('Apple 로그인 중 오류가 발생했습니다.');
    } on SignInWithAppleException {
      throw const SocialAuthException('Apple 로그인 중 오류가 발생했습니다.');
    }
  }

  Future<void> signOutGoogle() async {
    if (_googleInitialized) {
      await GoogleSignIn.instance.signOut();
    }
  }
}
