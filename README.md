# bbbook

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## 모바일 네이버 로그인 설정

네이버 Native SDK Access Token을 `POST /api/auth/mobile/naver/login`의
`{"token": "..."}`으로 전달합니다. 서비스 refreshToken은 기존 Secure Storage에
저장하며, 인증된 API의 401 refresh·1회 재시도는 기존 공통 인증 흐름을 사용합니다.

기존 웹 계정 연결을 위해 현재 웹과 동일한 Naver Application을 사용하며,
그 애플리케이션에 발급된 Client ID/Secret 쌍을 SDK에 설정합니다.
Secret 자체를 계정 연결 식별자로 사용하는 것은 아닙니다.
SDK가 요구하는 이 값들은 APK/IPA에서 추출할 수 있으므로 서버 전용 비밀값으로
취급할 수 없습니다. 별도 모바일 애플리케이션으로 분리하려면 기존 계정과의
연결 정책을 먼저 확인해야 합니다.

- Android: `android/local.properties`에 `naver.client_id=실제값`,
  `naver.client_secret=실제값`을 추가합니다. 네이버 개발자센터에 Android 환경과
  패키지명 `com.hagulu.nook.bbbook`, 해당 빌드의 서명을 등록합니다.
- iOS: `ios/Flutter/NaverKeys.xcconfig.sample`을 `NaverKeys.xcconfig`로 복사한 뒤
  실제 Client ID/Secret과 개발자센터에 등록한 URL Scheme을 설정합니다.
  Debug/Release/Profile 모두 이 설정을 사용합니다. 실제 키 파일은 Git에서 제외됩니다.
- iOS URL 콜백은 `naver_login_flutter` 4.0.0의 SceneDelegate 등록을 통해 처리합니다.
  기존 `FlutterSceneDelegate`를 유지해야 합니다.
- Android `MainActivity`는 기본 taskAffinity를 유지합니다. 빈 affinity에서는
  Chrome 인증 반환이 기존 작업(1771)이 아닌 새 작업(1772)의
  `NidOAuthCustomTabActivity`로 전달되는 기기 로그를 확인했고,
  기본값 복원 후 실기기 로그인 성공을 확인했습니다. 이 설정은 Flutter 템플릿의
  빈 affinity 보호를 사용하지 않는 선택이며, SDK Activity에도 빈 값을 설정하는
  대안은 아직 실기기에서 검증하지 않았습니다.

현재 카카오·네이버 버튼 SVG는 프로젝트 내 심볼이며 공식 배포 에셋으로
검증하지 않았습니다. 버튼 전체의 공식 디자인 가이드 준수를 보증하지 않습니다.

키를 입력한 뒤 앱을 다시 빌드해야 네이티브 SDK 설정에 반영됩니다. 키가 없는 빌드에서는
네이버 로그인 버튼을 눌렀을 때 설정 오류를 표시합니다.

SDK 연동 참고: [naver_login_flutter](https://pub.dev/packages/naver_login_flutter).
실기기 확인 시 네이버 앱 설치/미설치 로그인, 취소, 로그아웃 후 재로그인,
기존 웹 계정 연결 및 다른 계정 로그인 확인창을 확인합니다.

Android 카카오 로그인은 같은 `android/local.properties`에
`kakao.nativeAppKey=네이티브앱키`를 지정합니다. 앱은 이 값을 SDK 초기화와
리다이렉트 스킴에 함께 사용하므로 별도의 `KAKAO_NATIVE_APP_KEY` Dart define은
필요하지 않습니다. 변경 후 앱을 다시 빌드해야 합니다.
