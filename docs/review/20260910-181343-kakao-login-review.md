# 리뷰 결과

## 요약
- 미커밋된 카카오 로그인 연동을 검토했으며, 릴리스 앱 시작 실패·iOS 새 체크아웃 빌드 실패·SDK 초기화 경합·예외 분류 누락 등 4건을 확인했다. 모바일 로그인 API의 provider와 토큰 형식은 문서와 일치하며, `flutter analyze`는 통과했다.

## 문제점
- [문제][P1] 기존 릴리스 진입점으로 만든 앱은 시작 직후 종료된다.
  - 위치: `scripts/build_release_apk.sh:11`, `.vscode/launch.json:19-31`, `lib/core/config/kakao_config.dart:17-23`, `lib/main.dart:21`
  - `KakaoConfig.assertConfiguredForRelease()`는 릴리스에서 `KAKAO_NATIVE_APP_KEY`가 비어 있으면 `StateError`를 던진다. 그러나 저장소의 APK 빌드 스크립트와 두 릴리스 실행 구성은 모두 `API_BASE_URL`만 전달하고 새 키는 전달하지 않는다.
  - 따라서 빌드 자체는 성공할 수 있지만 생성된 릴리스 앱은 `runApp()` 전에 종료된다. Android redirect scheme용 `kakao.nativeAppKey`도 별도 로컬 설정이라, Dart define만 보완해도 두 값이 함께 설정된다는 보장이 없다.

- [문제][P1] 깨끗한 체크아웃에서는 iOS 빌드 설정 파일을 해석할 수 없다.
  - 위치: `ios/Flutter/Debug.xcconfig:2`, `ios/Flutter/Release.xcconfig:2`, `ios/.gitignore:22`, `ios/Flutter/Kakao.xcconfig.sample:1-3`
  - Debug와 Release 설정은 `#include "Kakao.xcconfig"`로 파일을 필수 포함하지만 실제 파일은 gitignore 대상이고 샘플만 추적된다. Profile도 Xcode 프로젝트에서 `Release.xcconfig`를 base configuration으로 사용하므로 세 구성 모두 같은 영향을 받는다.
  - 새로 체크아웃한 환경이나 CI에는 `Kakao.xcconfig`가 없어서, 카카오 로그인을 실행하기 전부터 Xcode가 필수 include를 찾지 못한다. 복사·주입 절차도 README나 빌드 스크립트에 연결되어 있지 않다.

- [문제][P2] 카카오 SDK 초기화 완료 전에 앱 시작 작업이 계속된다.
  - 위치: `lib/main.dart:22`
  - 사용 중인 `kakao_flutter_sdk_common 2.0.1`의 `KakaoSdk.init()`은 `Future<void>`이고, 네이티브 `PlatformInfo.create()`가 끝난 뒤 `KakaoSdk.platformInfo`를 설정한다. 현재 호출은 `await`하지 않아 이후 이미지 저장소·테마 초기화와 경합한다.
  - 카카오 로그인 첫 사용 시 생성되는 SDK HTTP client와 인증 경로는 `KakaoSdk.platformInfo`를 즉시 읽는다. 초기화가 늦거나 실패하면 `LateInitializationError` 또는 처리되지 않은 초기화 오류가 발생할 수 있으며, 뒤에 있는 다른 `await`들이 우연히 시간을 벌어 주는 것에 의존한다.

- [문제][P2] SDK가 구분하는 취소·실패 유형을 일부만 처리해 의도한 fallback이 동작하지 않는다.
  - 위치: `lib/features/auth/data/social_auth_service.dart:93-118`
  - `_loginWithKakaoTalkOrAccount()`는 카카오톡 로그인 실패를 카카오계정 로그인으로 대체한다고 설명하지만 `PlatformException`만 잡는다. SDK는 OAuth 응답 실패를 `KakaoAuthException`, 클라이언트 상태 실패를 `KakaoClientException`으로도 전달하므로 이 경우에는 계정 로그인으로 넘어가지 않는다.
  - 카카오 동의 화면 취소는 redirect 응답의 `access_denied`로 들어와 `KakaoAuthException(error: AuthErrorCause.accessDenied)`이 될 수 있다. 현재 코드는 모든 `KakaoAuthException`을 일반 오류로 바꿔, 사용자가 취소했는데도 "카카오 로그인 중 오류가 발생했습니다"를 표시한다.

## 개선 제안
- 릴리스 앱 시작 실패 → 릴리스 스크립트와 IDE 릴리스 구성에서 `KAKAO_NATIVE_APP_KEY`를 필수 입력으로 받아 `--dart-define`에 전달하고, Android manifest placeholder에도 같은 값을 전달한다. 빌드 전에 누락·불일치를 검사해 실행 시점이 아니라 아티팩트 생성 전에 실패시키는 편이 안전하다.
- iOS 새 체크아웃 빌드 실패 → CI·로컬 bootstrap 단계에서 샘플을 복사하고 값을 주입하는 절차를 저장소 문서와 빌드 흐름에 추가한다. 설정 없는 개발 빌드도 허용할 방침이면 `#include?`로 바꾸되, 카카오 버튼 비활성화와 릴리스 빌드 전 키 검증을 함께 둔다.
- SDK 초기화 경합 → `await KakaoSdk.init(nativeAppKey: KakaoConfig.nativeAppKey);`로 초기화를 완료한 뒤 나머지 시작 작업과 `runApp()`을 진행한다.
- 카카오 예외 분류 누락 → `PlatformException(code: CANCELED)`뿐 아니라 `KakaoAuthException.error == AuthErrorCause.accessDenied`와 `KakaoClientException.reason == ClientErrorCause.cancelled`도 취소로 분류한다. 카카오톡 fallback은 취소만 즉시 중단하고 그 밖의 SDK 로그인 실패를 카카오계정 로그인으로 넘긴 뒤, 최종 실패를 일관된 `SocialAuthException`으로 변환한다.
- 검증 → 키가 있는 Android/iOS에서 카카오톡 설치/미설치, 카카오톡 로그인 실패 후 계정 fallback, 두 로그인 방식의 사용자 취소를 확인한다. 릴리스 빌드는 키 누락 시 빌드 단계에서 실패하고 키가 있으면 앱 시작까지 진행되는지도 확인한다. 테스트는 이번 리뷰 요청 범위에 따라 실행하지 않았다.
