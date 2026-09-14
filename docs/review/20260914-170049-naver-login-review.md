# 리뷰 결과

## 요약
- Android 네이버 로그인은 성공 후 토큰을 받지 못해 항상 실패하며, iOS 콜백 연결과 Android 자격 증명 로그도 보완이 필요합니다. `flutter analyze`는 통과했습니다.

## 문제점
- [P1] Android 로그인 성공 후 Access Token 누락 — `lib/features/auth/data/social_auth_service.dart:151`: `flutter_naver_login` 2.1.1의 Android `logIn()`은 성공 시 `getCurrentAccount()`를 호출하며, 그 결과는 `status=loggedIn`과 `account`만 포함합니다. 따라서 여기서 읽는 `result.accessToken`은 항상 null이고, 실제 네이버 인증을 마쳐도 159행의 오류로 끝나 백엔드 로그인 요청이 전혀 나가지 않습니다.
- [P2] iOS 네이버 리다이렉트 콜백 미전달 — `ios/Runner/Info.plist:37`: URL 스킴만 추가했지만 `AppDelegate.swift`와 `SceneDelegate.swift`에는 `NidOAuth.shared.handleURL(url)` 호출이 없습니다. 플러그인 2.1.1의 iOS 구현도 앱 URL 콜백을 처리하지 않으며 README는 이 호출을 별도로 요구합니다. 네이버 인증 후 앱 URL로 돌아오는 경로에서 SDK가 결과를 받지 못해 로그인이 완료되지 않을 수 있습니다.
- [P2] Android 시작 시 네이버 Client Secret이 로그에 출력됨 — `android/app/src/main/AndroidManifest.xml:88`: 새로 연결한 `flutter_naver_login` 2.1.1은 플러그인 등록 때 메타데이터에서 `clientSecret`을 읽어 `println("ClientSecret: $clientSecret")`으로 출력하고 `showDevelopersLog(true)`를 켭니다. 실제 자격 증명을 주입한 릴리스에서도 앱 시작 때 값이 로그캣에 남습니다.

## 개선 제안
- Android 토큰 누락 → `logIn()` 성공 후 `FlutterNaverLogin.getCurrentAccessToken()`으로 토큰을 조회해 백엔드에 전달합니다.
- iOS 콜백 미전달 → 현재 Scene 기반 앱 수명주기에 맞는 URL 수신 지점에서 `NidOAuth.shared.handleURL(url)`을 호출하고 네이버 리다이렉트를 확인합니다.
- Client Secret 로그 노출 → 플러그인 로그 출력을 제거하거나 패치한 버전을 사용하고 릴리스 구성에서 개발자 로그를 비활성화합니다.

정적 분석만 수행했습니다. 프로젝트 지침에 따라 앱 실행과 테스트는 하지 않아 네이티브 로그인 왕복 동작은 검증되지 않았습니다.
