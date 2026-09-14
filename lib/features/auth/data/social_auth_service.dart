import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:naver_login_flutter/naver_login_flutter.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/config/kakao_config.dart';

/// 소셜 로그인 실패 시 화면에 노출할 메시지를 담는 예외.
class SocialAuthException implements Exception {
  const SocialAuthException(this.message);
  final String message;
}

/// 네이티브 소셜 SDK에서 백엔드 검증용 ID 토큰 또는 Access Token을 얻는다.
class SocialAuthService {
  static const _socialConfigChannel = MethodChannel(
    'com.hagulu.nook.bbbook/social_config',
  );
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

  Future<String> signInWithNaver() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw const SocialAuthException('현재 플랫폼에서는 네이버 로그인을 지원하지 않습니다.');
    }
    try {
      final configured = await _socialConfigChannel.invokeMethod<bool>(
        'isNaverConfigured',
      );
      if (configured != true) {
        throw const SocialAuthException('네이버 로그인 설정이 필요합니다. 앱 관리자에게 문의해 주세요.');
      }
      await FlutterNaverLogin.setLogEnabled(false);
      final result = await FlutterNaverLogin.logIn().timeout(
        const Duration(seconds: 90),
        onTimeout: () =>
            throw const SocialAuthException('네이버 로그인 응답이 없습니다. 다시 시도해 주세요.'),
      );
      if (result.status == NaverLoginStatus.loggedOut ||
          (result.errorMessage?.toLowerCase().contains('cancel') ?? false)) {
        developer.log(
          '[소셜 로그인] provider=naver result=FAIL '
          'reason=sdk_canceled status=${result.status.name}',
        );
        throw const SocialAuthException('로그인이 취소되었습니다.');
      }
      if (result.status != NaverLoginStatus.loggedIn) {
        developer.log(
          '[소셜 로그인] provider=naver result=FAIL reason=sdk_login_failed',
        );
        throw const SocialAuthException('네이버 로그인에 실패했습니다. 다시 시도해 주세요.');
      }
      // 로그인 결과의 프로필이 아닌 SDK에 저장된 Access Token을 전달한다.
      final token = await FlutterNaverLogin.getCurrentAccessToken();
      if (token.accessToken.trim().isEmpty) {
        developer.log(
          '[소셜 로그인] provider=naver result=FAIL reason=missing_access_token',
        );
        throw const SocialAuthException('네이버 인증 정보를 가져오지 못했습니다.');
      }
      return token.accessToken;
    } on SocialAuthException {
      rethrow;
    } catch (_) {
      developer.log('[소셜 로그인] provider=naver result=FAIL reason=sdk_error');
      throw const SocialAuthException('네이버 로그인 중 오류가 발생했습니다.');
    }
  }

  Future<void> signOutNaver() async {
    try {
      await FlutterNaverLogin.logOut();
    } catch (_) {
      developer.log('[소셜 로그아웃] provider=naver result=FAIL reason=sdk_error');
    }
  }

  Future<void> signOutGoogle() async {
    if (_googleInitialized) {
      await GoogleSignIn.instance.signOut();
    }
  }

  /// 카카오톡 설치 시 카카오톡으로, 아니면 카카오계정으로 로그인해 Kakao
  /// Access Token을 반환한다. 백엔드 검증 용도로만 쓰이며 서비스 자체
  /// 인증 토큰으로 사용하지 않는다.
  Future<String> signInWithKakao() async {
    if (!KakaoConfig.isConfigured) {
      throw const SocialAuthException('카카오 로그인 설정이 필요합니다. 앱 관리자에게 문의해 주세요.');
    }
    try {
      final talkInstalled = await isKakaoTalkInstalled();
      final token = talkInstalled
          ? await _loginWithKakaoTalkOrAccount()
          : await UserApi.instance.loginWithKakaoAccount();
      return token.accessToken;
    } catch (e) {
      if (_isKakaoLoginCanceled(e)) {
        throw const SocialAuthException('로그인이 취소되었습니다.');
      }
      throw const SocialAuthException('카카오 로그인 중 오류가 발생했습니다.');
    }
  }

  /// 카카오톡 로그인이 (설치되어 있음에도) 실패하면 카카오계정 로그인으로
  /// 대체한다. 단, 사용자가 취소한 경우까지 대체 로그인으로 넘어가지 않는다.
  Future<OAuthToken> _loginWithKakaoTalkOrAccount() async {
    try {
      return await UserApi.instance.loginWithKakaoTalk();
    } catch (e) {
      if (_isKakaoLoginCanceled(e)) rethrow;
      return UserApi.instance.loginWithKakaoAccount();
    }
  }

  /// 카카오톡 로그인은 [PlatformException]('CANCELED'), 카카오계정 로그인(동의
  /// 화면)은 [KakaoAuthException](accessDenied), SDK 클라이언트 단 취소는
  /// [KakaoClientException](cancelled)으로 각각 다르게 취소를 알려준다.
  bool _isKakaoLoginCanceled(Object error) {
    return switch (error) {
      PlatformException(:final code) => code == 'CANCELED',
      KakaoAuthException(error: final cause) =>
        cause == AuthErrorCause.accessDenied,
      KakaoClientException(:final reason) =>
        reason == ClientErrorCause.cancelled,
      _ => false,
    };
  }

  Future<void> signOutKakao() async {
    try {
      await UserApi.instance.logout();
    } catch (_) {
      // 다음 카카오 로그인 시도에서 계정 선택 화면이 다시 뜨는 정도의 영향만 있다.
    }
  }
}
