import 'package:flutter/foundation.dart';

class KakaoConfig {
  const KakaoConfig._();

  // Kakao Developers 콘솔의 네이티브 앱 키. 코드에 직접 적지 않고
  // `flutter run --dart-define=KAKAO_NATIVE_APP_KEY=실제-네이티브-앱-키`로 주입한다.
  // Android는 android/local.properties의 kakao.nativeAppKey, iOS는
  // ios/Flutter/Kakao.xcconfig의 KAKAO_NATIVE_APP_KEY에 동일한 값을 별도로 설정해야
  // 네이티브 매니페스트/Info.plist의 커스텀 URL 스킴도 맞춰진다.
  static const String nativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
  );

  /// release 빌드에 네이티브 앱 키가 비어있는 채로 배포되는 것을 막는다.
  /// `main()`에서 앱 시작 전에 한 번 호출한다.
  static void assertConfiguredForRelease() {
    if (kReleaseMode && nativeAppKey.isEmpty) {
      throw StateError(
        'KAKAO_NATIVE_APP_KEY가 설정되지 않았습니다. release 빌드는 반드시 '
        '--dart-define=KAKAO_NATIVE_APP_KEY=실제-네이티브-앱-키 로 지정해야 합니다.',
      );
    }
  }
}
