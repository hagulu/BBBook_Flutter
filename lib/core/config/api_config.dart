import 'package:flutter/foundation.dart';

class ApiConfig {
  const ApiConfig._();

  static const String _devDefault = 'http://192.168.0.51:8080';

  // 기본값은 로컬 개발 PC의 LAN IP(실기기는 localhost로 접근 불가).
  // 다른 백엔드 주소가 필요하면 코드 수정 없이
  // `flutter run --dart-define=API_BASE_URL=http://호스트:포트`로 덮어쓸 수 있다.
  // Wi-Fi 재연결 등으로 PC IP가 바뀌면 기본값도 갱신 필요.
  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  static const String baseUrl =
      _definedBaseUrl != '' ? _definedBaseUrl : _devDefault;

  /// release 빌드에 `API_BASE_URL`이 지정되지 않은 채 배포되는 것을 막는다.
  /// 값 자체가 개발 기본값과 같아도 명시적으로 지정했다면 허용한다.
  /// `main()`에서 앱 시작 전에 한 번 호출한다.
  static void assertConfiguredForRelease() {
    if (kReleaseMode && _definedBaseUrl == '') {
      throw StateError(
        'API_BASE_URL이 설정되지 않았습니다. release 빌드는 반드시 '
        '--dart-define=API_BASE_URL=https://실제-백엔드-주소 로 지정해야 합니다.',
      );
    }
  }
}
