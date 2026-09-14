import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class KakaoConfig {
  const KakaoConfig._();

  // Android와 iOS의 Redirect URI에 이미 사용한 네이티브 앱 키를 SDK에도 쓴다.
  static const _configChannel = MethodChannel(
    'com.hagulu.nook.bbbook/social_config',
  );
  static bool isConfigured = false;

  static Future<String> loadNativeAppKey() async {
    isConfigured = false;
    try {
      final key =
          await _configChannel.invokeMethod<String>('getKakaoNativeAppKey') ??
          '';
      isConfigured = key.trim().isNotEmpty && !key.contains(r'$(');
      return isConfigured ? key : '';
    } on PlatformException {
      developer.log('[카카오 설정 조회] result=FAIL reason=platform_error');
      return '';
    } on MissingPluginException {
      developer.log('[카카오 설정 조회] result=FAIL reason=missing_plugin');
      return '';
    }
  }

  /// release 빌드에 네이티브 앱 키가 비어있는 채로 배포되는 것을 막는다.
  /// `main()`에서 앱 시작 전에 한 번 호출한다.
  static void assertConfiguredForRelease() {
    if (kReleaseMode && !isConfigured) {
      throw StateError(
        '카카오 네이티브 앱 키가 설정되지 않았습니다. Android는 '
        'android/local.properties의 kakao.nativeAppKey, iOS는 '
        'ios/Flutter/Kakao.xcconfig의 KAKAO_NATIVE_APP_KEY를 설정하세요.',
      );
    }
  }
}
