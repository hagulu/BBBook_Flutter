import 'package:flutter/foundation.dart';

class ApiConfig {
  const ApiConfig._();

  static const String _devDefault = 'http://192.168.0.51:8080';

  // 기본값은 로컬 개발 PC의 LAN IP(실기기는 localhost로 접근 불가).
  // 다른 백엔드 주소가 필요하면 코드 수정 없이
  // `flutter run --dart-define=API_BASE_URL=http://호스트:포트`로 덮어쓸 수 있다.
  // Wi-Fi 재연결 등으로 PC IP가 바뀌면 기본값도 갱신 필요.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _devDefault,
  );

  /// release 빌드에 로컬 개발용 기본값이 그대로 들어간 채 배포되는 것을 막는다.
  /// `main()`에서 앱 시작 전에 한 번 호출한다.
  static void assertConfiguredForRelease() {
    if (kReleaseMode && baseUrl == _devDefault) {
      throw StateError(
        'API_BASE_URL이 설정되지 않았습니다. release 빌드는 반드시 '
        '--dart-define=API_BASE_URL=https://실제-백엔드-주소 로 지정해야 합니다.',
      );
    }
  }
}
