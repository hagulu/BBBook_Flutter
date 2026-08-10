# BBBook

Flutter 기반의 독서 기록 서비스 앱 프로젝트

## 버전
- Flutter 3.44.8 (stable)
- Dart 3.12.2

## 기본 규칙
- 상태가 필요 없으면 StatelessWidget, 필요한 경우에만 StatefulWidget 사용
- screen(화면)은 얇게 유지하고 로직은 model/service로 분리
- 디렉토리 구조는 `structure` 스킬 기준(`lib/app`, `lib/core`, `lib/features`, `lib/shared/widgets`)을 따른다.
- 기존 공통 위젯, 상태관리, 유틸을 우선 재사용한다.
- 요청받은 기능만 구현하며, 범위를 벗어나는 리팩터링이나 개선은 하지 않는다.
- 추가 구현이 필요하다고 판단되면 먼저 사용자에게 확인한다.

## 작업 흐름
- 작업 전 `docs/file-index.md`를 확인하여 기존 구조와 파일 위치를 파악한다.
- 작업 완료 후 `flutter analyze`를 실행한다.
- 앱 실행(`flutter run`, 에뮬레이터/디바이스 구동 등)은 하지 않는다.
- 테스트는 요청 시에만 실행한다.
- 테스트 코드는 검증이 꼭 필요한 비즈니스 로직에만 작성한다.

## 인증 API 호출
- API 구현 전 `api-read` 스킬 기준으로 `../../api-doc/*.md`를 먼저 확인한다.
- API 요청 시 401이면 refresh 토큰 재발급 후 1회 재시도하고, 실패하면 로그아웃 처리한다.

## 아이콘
- 아이콘은 `phosphor_icons` 패키지의 `PhosphorIconsRegular`(기본)/`PhosphorIconsFill`(채워진 상태 표현)을 사용한다(`phosphor_flutter`는 최신 Flutter의 `IconData` final class 변경과 호환되지 않아 사용 금지).
- 채워진 아이콘이 필요한 경우 커스텀 페인터로 직접 그리지 않고 `PhosphorIconsFill`을 우선 사용한다.

## 전역 Alert/Confirm/Loading
- 화면별 커스텀 팝업·로딩을 만들지 않고 `lib/shared/widgets/`의 공통 컴포넌트를 사용한다.
  - Alert: `AppAlert.show()`
  - Confirm: `AppConfirm.show()` — `Future<bool>` 반환
  - Loading(전체 화면): `AppLoading.show()` / `AppLoading.hide()`
  - Loading(영역 단위): `AppLoadingOverlay` 위젯

## 백엔드
- API 문서만으로 해결 가능한 경우 백엔드 소스를 확인하지 않는다.
- 백엔드 소스 확인이 필요하면 먼저 이유를 설명하고 사용자에게 확인받은 후 진행한다.

## MCP
- 명시적으로 요청된 경우만 사용한다.