# 리뷰 결과

## 요약
서버 삭제 전에 로컬 모드를 확정하고 이미지 누락을 확인하는 순서는 적절합니다. 별도 독립 결함을 추가하지 않았으며, 가져오기와의 동시 실행 문제는 IMP-02로 통합했습니다.

## 확인 범위
설정에서 동기화 끄기, 동기화 실패 후 계속 진행 여부, 전체 records 적용, 메모·독후감·표지 다운로드, 누락 집계, exportedAt 기반 삭제, 서버 변경 충돌 재조회, 남은 서버 정리 재시도를 확인했습니다.

## 문제점

- [IMP-02][P1] 화면 밖에서 계속 실행되는 외부 가져오기를 설정의 동기화 끄기가 확인하지 않습니다. 자세한 조건과 근거는 [외부 가져오기 리뷰](../03-imports/20261028-124818-external-import.md)에 있습니다. 같은 원인을 중복 집계하지 않았습니다.
- [AUTH-01][P1], [AUTH-02][P2] 로컬 전환 후 로그아웃·재로그인의 소유권 문제는 [인증 리뷰](../01-auth/20261028-124818-login-logout-ownership.md)에 있습니다.
- 설정의 전환 확인 문구와 실제 로그아웃 정책이 다른 문제는 [SET-01](../07-profile/20261028-124818-profile-settings-stats.md)로 기록했습니다.

## 개선 제안

전환 서비스의 기존 삭제 순서는 유지하고, 외부 가져오기를 포함한 작업 배타 조건과 로그아웃 메타만 해당 경계에서 고치는 것이 우선입니다.

## 확인된 보호 장치

- [lib/features/storage_mode/services/local_storage_migration_service.dart:188](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/storage_mode/services/local_storage_migration_service.dart:188): 최신 기록을 못 받으면 사용자가 계속할지 선택합니다.
- 이미지 파일 유무를 다시 점검하고 메모·독후감·직접 업로드한 표지를 모두 확보합니다. 받을 수 없는 이미지와 일시 실패를 구분합니다.
- [lib/features/storage_mode/data/local_storage_migration_steps.dart:190](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/storage_mode/data/local_storage_migration_steps.dart:190): 로컬 모드를 먼저 기록하고 진행 중 동기화를 기다린 뒤 서버를 정리합니다.
- `exportedAt` 이후 서버 변경은 409로 거절되며, 같은 실행의 재조회에서는 이미지 검증 뒤에만 정리 기준을 갱신합니다.
- 나중에 정리만 재시도할 때는 현재 로컬 편집을 서버 스냅샷으로 덮지 않습니다. 이미지 누락과 서버 변경을 무시하려면 각각 사용자 선택을 받습니다.

## 기기 확인 항목

다운로드 도중 홈 전환 후 복귀, 이미지 한 장 실패 후 재시도, 로컬 모드 확정 직후 앱 종료, 서버 정리만 실패한 뒤 재실행을 확인합니다. 실제 기기 실행은 이번 리뷰에서 하지 않았습니다.
