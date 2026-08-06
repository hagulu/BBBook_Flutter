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
- 아이콘은 Material Icons를 우선 사용하고, 필요 시 `cupertino_icons` 사용

## 전역 Alert/Confirm
- 신규 기능 및 수정 작업에서 브라우저성/화면별 커스텀 팝업을 만들지 않는다
- 사용자 안내/성공/실패/경고는 `ScaffoldMessenger`(SnackBar), 확인 요청은 `showDialog<bool>()`(AlertDialog)를 사용한다
- 자세한 사용 기준은 `alert-system` 스킬을 따른다
- 기존 코드에서 화면별 중복 확인 다이얼로그가 발견되면 공통 방식으로 교체한다

## 백엔드
- 백엔드 관련 문제가 생기면 소스를 직접 열지 말고 사용자에게 먼저 확인한다

## MCP
- 명시적으로 요청된 경우만 사용
