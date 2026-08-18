# 리뷰 결과

## 요약
- 최초 기록 동기화(`record_sync`) 기능 자체는 세션 세대 체크, 트랜잭션 원자성 등 기존 코드베이스 패턴을 잘 따르고 있으나, 동기화 실패 시 사용자가 앱에서 빠져나갈 방법이 없는 라우팅 문제와 파일 인덱스 누락이 있다.

## 문제점
- [문제] `InitialRecordSyncGate`(`lib/features/record_sync/screens/initial_record_sync_screen.dart`)가 `/feed` 진입을 완전히 막고, 실패(`failed`) 상태에서는 "다시 시도" 버튼만 제공한다. 로그아웃 버튼은 `MainShell` 내부 프로필 탭(`lib/features/profile/screens/profile_tab_placeholder.dart`)에만 있는데, 이 화면은 동기화가 완료돼야 렌더링되는 `child`이므로 도달할 수 없다. 뒤로 가기 처리도 없어(Scaffold에 AppBar/leading 없음, `/feed`가 `/`에서 redirect로 대체된 라우트라 back stack도 없음) 네트워크 장애가 지속되면 사용자가 로그인 계정을 바꾸거나 로그아웃할 방법 없이 이 화면에 영구히 갇힌다.
- [문제] `docs/file-index.md`에 `lib/features/record_sync/data/record_sync_dao.dart`와 `lib/features/record_sync/models/record_sync_payload.dart`가 등록되지 않았다. 같은 기능의 다른 파일(`record_sync_api.dart`, `record_sync_repository.dart`, `providers`, `screens`)은 등록됐지만 이 두 파일만 누락됐다.

## 개선 제안
- 문제 → 개선 방법: `_InitialRecordSyncScreen`의 실패 상태에 "다시 시도" 외에 로그아웃(또는 뒤로 가기) 진입점을 추가해, 동기화가 계속 실패해도 사용자가 계정을 전환하거나 앱에서 벗어날 수 있게 한다.
- 문제 → 개선 방법: `docs/file-index.md`의 `features/record_sync` 섹션에 `record_sync_dao.dart`, `models/record_sync_payload.dart` 항목을 추가한다.
