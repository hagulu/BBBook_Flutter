# 리뷰 결과

## 요약

- 전체 상태: `main`/`app`/`feature` 분리, Riverpod DI, go_router, 공통 API 클라이언트 도입 방향은 적절하지만, 인증 계층의 책임 혼합과 실제 세션·플랫폼 오류가 남아 있어 현재 상태를 그대로 후속 구현의 표준으로 확정하기에는 이르다.
- 아키텍처 판정: 현재 Flutter 공식 권고의 핵심인 UI·데이터 계층 분리, Repository/Service, View/ViewModel 중 View·상태관리·Service에 해당하는 요소는 있으나 Repository 경계가 빠져 있다. Riverpod과 go_router 선택 자체는 일반적인 Flutter 구조에서 벗어나지 않는다. 공식 문서도 상태관리 방식은 선택 사항으로 두고 go_router를 일반 앱에 권장한다. ([Flutter 아키텍처 권고](https://docs.flutter.dev/app-architecture/recommendations), [Flutter 앱 아키텍처 가이드](https://docs.flutter.dev/app-architecture/guide))
- 공통 컴포넌트 판정: `SocialLoginButton`을 전역 `shared`가 아니라 인증 feature 내부에 둔 것은 적절하다. 현재 한 화면에서만 쓰는 위젯을 성급하게 공통화하지 않은 점도 좋다. 반면 인증 전용 `AuthLoadingGate`가 `shared`에 있고 feature가 `app/theme.dart`를 참조하는 의존 방향은 기준으로 삼기 어렵다.
- 잘된 점: `main.dart`가 `ProviderScope`와 루트 앱 실행만 담당하고, 라우팅·테마·화면·API·스토리지가 분리되어 있다. refresh token은 secure storage에, access token은 메모리에 보관하며, `ApiClient`가 콜백 주입으로 `core`에서 auth feature를 직접 참조하지 않는 방향도 적절하다.
- 위젯 판정: 화면 고유의 로그인 진행 상태 때문에 `OnboardingScreen`을 `StatefulWidget`으로 둔 것은 타당하다. 비동기 작업 후 `mounted`를 확인하고, `select`로 관찰 범위를 줄였으며, 스크롤·안전 영역과 52px 버튼 높이도 기본 접근성/레이아웃 측면에서 문제를 찾지 못했다.
- 검증: `flutter analyze` 결과 error/warning은 없고 `AuthApi` 생성자의 `prefer_initializing_formals` info 3건만 있다. 이는 동작이나 아키텍처 문제는 아니므로 아래 문제점에는 포함하지 않았다. 요청 지침에 따라 앱 실행과 테스트는 수행하지 않았다.

## 문제점

- [높음][인증] 401 재시도 요청도 401로 실패하면 로그아웃되지 않는다. `lib/core/network/api_client.dart:59`는 `alreadyRetried`인 모든 오류를 그대로 전달한다. 따라서 refresh 성공 후 새 access token까지 거부된 경우에도 `_onUnauthorized`가 호출되지 않아, “401 → refresh 1회 → 재요청 실패 시 로그아웃” 규칙을 충족하지 못한다.
- [높음][인증 상태] 일시적인 네트워크/서버 장애를 인증 만료와 동일하게 처리한다. `lib/features/auth/providers/auth_notifier.dart:54`는 `getMe()`의 모든 `ApiException`에서 refresh token을 지우고 로그아웃한다. 반대로 앱 시작 refresh가 timeout/500으로 실패하면 `lib/features/auth/providers/auth_notifier.dart:43`에서 미인증 상태로 바꾸면서 저장된 refresh token은 남긴다. 같은 장애가 경로에 따라 “세션 파기” 또는 “로그인 화면 전환”으로 다르게 처리되고, 사용자에게 재시도 가능한 오류 상태도 제공하지 않는다.
- [높음][플랫폼/네트워크] 현재 설정으로는 플랫폼별 인증 API가 정상 동작하지 않는 구간이 있다. Android의 `INTERNET` 권한이 debug/profile manifest에만 있고 `android/app/src/main/AndroidManifest.xml`에는 없어 release 빌드의 네트워크 요청이 실패한다. Android 공식 문서도 네트워크 작업에 manifest의 `INTERNET` 권한을 요구한다. ([Android 네트워크 연결 문서](https://developer.android.com/develop/connectivity/network-ops/connecting))
- [높음][환경 설정] `lib/core/config/api_config.dart:6`의 사설 LAN HTTP 주소가 모든 빌드에 고정되어 있다. iOS `Info.plist`에는 ATS 예외가 없어 로컬 HTTP 요청이 기본적으로 차단되며, release도 개발 서버 주소를 사용하게 된다. Apple은 ATS가 기본적으로 안전하지 않은 HTTP 연결을 차단한다고 명시한다. ([Apple ATS 문서](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity))
- [높음][소셜 로그인] iOS 네이티브 설정이 구현과 일치하지 않는다. Xcode 프로젝트의 bundle ID는 여전히 `com.example.bbbook`이고, Google 로그인 복귀에 필요한 `CFBundleURLTypes` URL scheme이 없으며, Sign in with Apple capability/entitlements 연결도 없다. Dart에서 Google client ID를 전달해도 iOS URL scheme은 별도로 필요하다. ([google_sign_in_ios 설정](https://pub.dev/packages/google_sign_in_ios), [sign_in_with_apple 설정](https://pub.dev/packages/sign_in_with_apple)) `isAppleSignInSupported`는 iOS/macOS라는 이유만으로 `true`를 반환하므로 실제 설정이 없는 iOS에서도 버튼이 활성화된다.
- [중간][구조] `AuthNotifier`가 ViewModel과 Repository 역할을 동시에 수행한다. `lib/features/auth/providers/auth_notifier.dart`는 UI가 관찰하는 인증 상태뿐 아니라 소셜 SDK, API, secure storage, 토큰 회전, 앱 부트스트랩, 401 콜백 구성까지 소유한다. 인증 세션은 여러 화면과 라우터가 함께 사용하는 앱 전역 source of truth이므로 Repository가 맡기에 적합한 상태다. 현재 패턴을 후속 feature가 복제하면 각 Notifier가 API·캐시·재시도까지 직접 관리하게 되어 데이터 계층의 경계와 단위 테스트 대역이 불명확해진다.
- [중간][의존 방향] 하위 계층이 상위 조립 계층 또는 다른 feature를 역참조한다. `lib/features/auth/screens/onboarding_screen.dart:4`가 `lib/app/theme.dart`를 참조해 `features → app` 의존이 생기고, `lib/shared/widgets/auth_loading_gate.dart:4`는 auth feature를 참조해 “모든 feature가 사용할 수 있는 shared”가 특정 feature에 종속된다. `lib/app`이 feature를 조립하는 현재 구조에서는 feature가 다시 `app`에 의존하지 않도록 해야 한다.
- [중간][비동기 상태] `Notifier.build()`에서 `Future.microtask(_bootstrap)`을 시작하지만 Future를 상태로 추적하지 않는다. `lib/features/auth/providers/auth_notifier.dart:36` 이후 secure storage나 예상 밖 플랫폼 예외가 발생하면 오류가 관찰되지 않은 채 `authLoading`에 머물 수 있다. Riverpod은 비동기 초기화와 loading/error/data 표현에 `AsyncNotifier`를 제공하므로, 현재의 수동 microtask보다 수명주기와 오류 상태가 명확하다. ([Riverpod (Async)NotifierProvider](https://docs-v2.riverpod.dev/docs/providers/notifier_provider))
- [중간][응답 타입] JSON 형 변환 실패가 도메인 오류로 정규화되지 않는다. `AuthTokens.fromJson`과 `AuthUser.fromJson`의 직접 `as` 캐스팅에서 `TypeError`가 발생하면 `AuthApi`의 `DioException` 매핑 및 화면의 `ApiException` 처리 범위를 모두 벗어난다. 부트스트랩 중이면 인증 로딩이 끝나지 않을 수 있다. 또한 API 문서상 로그인/refresh 응답의 `refreshToken`은 필수인데 모델에서는 nullable이어서 잘못된 성공 응답을 허용한다.
- [중간][네트워크 공통 설정] 인증 전용 `Dio`에는 timeout이 없다. `lib/features/auth/providers/auth_providers.dart:13`은 base URL만 설정하지만 공통 `ApiClient`는 connect/receive timeout을 10초로 둔다. 로그인·앱 시작 refresh·로그아웃이 응답 없는 서버에서 무기한 대기할 수 있고, 두 클라이언트의 기본 설정이 앞으로 더 어긋날 가능성이 있다.
- [중간][검증 기반] 최초 구현에서 기본 widget test는 삭제됐고 인증 핵심 로직을 검증하는 테스트가 없다. 테스트를 모든 단순 위젯에 추가할 필요는 없지만, 동시 401 단일 refresh, 재시도 401 로그아웃, refresh token 회전 저장, 시작 상태 전이, 라우터 redirect는 실패 시 앱 전체 세션에 영향을 주는 비즈니스 로직이다. 현재처럼 콜백과 concrete service가 한 Notifier에 모여 있으면 이 핵심 경로를 격리 검증하기도 어렵다.
- [낮음][임시 화면 위치] `lib/app/placeholder_home_screen.dart`가 앱 조립 계층에 화면과 로그아웃 UI를 포함한다. TODO가 명확한 임시 스텁이므로 현재 차단 문제는 아니지만, 실제 feed 구현 시에는 `features/home_feed/screens` 등 feature 아래로 교체해야 하며 `app` 화면 배치의 선례로 남기면 안 된다.

## 개선 제안

- 재시도 401이 로그아웃되지 않음 → `_onError`에서 `401 && alreadyRetried`를 별도 처리해 `_onUnauthorized`를 호출한 뒤 오류를 전달한다. timeout/500처럼 재시도 요청의 비인증 오류까지 로그아웃으로 취급하지 않도록 상태 코드를 구분하고, 동시 실패 시 로그아웃 처리도 한 번만 수행되게 한다.
- 일시 장애와 인증 만료가 혼재함 → `ApiException`을 최소한 인증 실패(401/필요 시 403), 재시도 가능한 네트워크/5xx, 응답 형식 오류로 구분한다. refresh/getMe에서 실제 인증 무효일 때만 저장 토큰을 지우고, 일시 장애는 `error + retry` 상태를 노출한다.
- 인증 상태와 데이터 오케스트레이션이 한 Notifier에 있음 → auth feature에 `AuthRepository` 경계를 추가해 `AuthApi`, `SocialAuthService`, `TokenStorage` 조합과 세션 source of truth를 맡긴다. `AuthNotifier`는 repository 한 개에 의존해 화면/라우터가 사용할 상태와 명령만 노출한다. 현재 복잡도에서는 별도 domain/use-case 계층까지 추가할 필요는 없다.
- 비동기 부트스트랩이 추적되지 않음 → Repository 분리와 함께 `AsyncNotifier` 또는 명시적인 `AuthState(error, retry)`로 초기화를 모델링한다. `build()`의 fire-and-forget microtask를 제거하고 초기화 완료·실패·재시도 경로가 모두 상태 전이로 보이게 한다.
- 계층 의존이 역전됨 → 테마/색상 토큰은 `lib/core/theme/`처럼 feature와 app이 함께 아래 방향으로 참조할 위치로 옮긴다. `AuthLoadingGate`는 auth 전용이면 `features/auth/widgets`, 라우팅 조립 전용이면 `app`에 둔다. `shared/widgets`에는 feature를 몰라도 동작하는 위젯만 둔다.
- 공통 UI 기준이 아직 색상 상수에 치우침 → `ThemeData`/`ColorScheme`/`TextTheme`와 component theme를 우선 사용하고, 소셜 브랜드색처럼 앱 테마와 무관한 예외만 feature 전용 상수로 둔다. 현 단계에서는 spacing/radius용 공통 클래스를 선제적으로 늘리지 말고 두 개 이상 화면에서 실제 반복될 때 추출한다.
- 응답 캐스팅 오류가 새어 나감 → 응답 DTO 파싱에서 필수 필드와 타입을 검증하고 모든 형식 오류를 일관된 data-format 예외로 변환한다. 로그인/refresh용 토큰 응답에서는 `refreshToken`을 non-nullable로 모델링해 API 계약 위반을 즉시 실패 처리한다.
- 인증용 Dio 설정이 분기됨 → 공통 `BaseOptions` 또는 Dio factory에서 base URL과 timeout을 한 번 정의하고, Authorization/401 interceptor 적용 여부만 클라이언트별로 선택한다.
- 플랫폼 네트워크 설정이 미완성임 → Android `INTERNET` 권한을 main manifest로 옮기고, base URL은 `--dart-define` 또는 flavor별 설정으로 주입한다. production은 HTTPS만 사용하고 iOS 로컬 HTTP 예외가 꼭 필요하면 debug 설정에만 최소 범위로 둔다.
- iOS 소셜 로그인 설정이 미완성임 → Android와 동일한 실제 bundle ID로 Xcode 설정을 맞춘 뒤 Google reversed client URL scheme, Sign in with Apple capability, entitlements 및 provisioning profile을 연결한다. 버튼 지원 여부도 단순 플랫폼 비교가 아니라 SDK availability/설정 상태를 반영한다.
- 핵심 세션 검증이 없음 → Repository/Notifier를 provider override 또는 fake로 대체 가능하게 만든 뒤, 인증 비즈니스 로직 단위 테스트와 router redirect widget test만 우선 추가한다. 일반 UI 스냅샷 테스트나 단순 모델 getter 테스트까지 범위를 넓힐 필요는 없다.
- 임시 홈 화면이 app에 있음 → home-feed 이관 시 실제 screen으로 라우트를 교체하고 placeholder 파일을 삭제한다. `lib/app`에는 루트 앱, 라우터, 전역 조립 책임만 남긴다.

