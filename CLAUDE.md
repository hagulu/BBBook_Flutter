# BBBook

Flutter 기반의 독서 기록 서비스 앱 프로젝트

## 버전
- Flutter 3.44.8 (stable)
- Dart 3.12.2

## 기본 규칙
- 상태가 필요 없으면 StatelessWidget, 필요한 경우에만 StatefulWidget 사용
- screen(화면)은 얇게 유지하고 로직은 model/service로 분리
- 디렉토리 구조는 `structure` 스킬 기준(`lib/app`, `lib/core`, `lib/features`, `lib/shared/widgets`)을 따른다

## 작업 흐름
- `flutter analyze` → `flutter build`
- 앱 실행(`flutter run`, 에뮬레이터/디바이스 구동 등)은 하지 않는다
- 테스트는 요청 시에만 실행
- 테스트 코드는 검증이 꼭 필요한 비즈니스 로직에만 작성

## 파일 인덱스
- `docs/file-index.md` 우선 확인

## 인증 API 호출
- API 요청 시 401이면 refresh 토큰 재발급 후 1회 재시도, 실패 시 로그아웃 처리
- API 요청 구현 전 `api-read` 스킬 기준으로 문서(`../../api-doc/*.md`)를 먼저 확인

## 아이콘
- 아이콘은 `phosphor_icons` 패키지의 `PhosphorIconsRegular`(기본)/`PhosphorIconsFill`(채워진 상태 표현)을 사용한다(`phosphor_flutter`는 최신 Flutter의 `IconData` final class 변경과 호환되지 않아 사용 금지)
- 채워진 아이콘이 필요한 경우 커스텀 페인터로 직접 그리지 않고 `PhosphorIconsFill`을 우선 사용한다

## 전역 Alert/Confirm/Loading/SnackBar
- 신규 기능 및 수정 작업에서 화면별 커스텀 팝업·로딩·스낵바를 만들지 않고 아래 공통 컴포넌트(`lib/shared/widgets/`)를 사용한다
  - Alert: `AppAlert.show()` — 제목/내용/확인 버튼
  - Confirm: `AppConfirm.show()` — 제목/내용/확인·취소 버튼, `Future<bool>` 반환
  - Loading(전체 화면): `AppLoading.show()` / `AppLoading.hide()` — 중첩 호출 안전(참조 카운트), `hide()`는 반드시 `finally`에서 호출
  - Loading(영역 단위): `AppLoadingOverlay` 위젯 — `isLoading`으로 제어
  - SnackBar: `AppSnackBar.success()` / `.info()` / `.error()` — pill 형태, 성공·정보는 아이덴티티 컬러, 에러는 에러 컬러 반투명 배경 + 상태 아이콘
- 사용자 안내/성공/실패/경고는 `AppSnackBar`, 확인 요청은 `AppConfirm`을 사용한다
- 기존 코드에서 화면별 중복 확인 다이얼로그·로딩·SnackBar가 발견되면 위 공통 컴포넌트로 교체한다

## 백엔드
- 백엔드 관련 문제가 생기면 소스를 직접 열지 말고 사용자에게 먼저 확인한다

## MCP
- 명시적으로 요청된 경우만 사용
