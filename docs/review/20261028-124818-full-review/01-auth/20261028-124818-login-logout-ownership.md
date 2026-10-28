# 리뷰 결과

## 요약
로그인 복구와 일반 API의 세션 차단은 갖추고 있지만, 로컬 모드에서 로그아웃한 뒤의 계정 복원과 서버 ID 소유권에 문제가 있습니다. P1 1건, P2 1건입니다.

## 확인 범위
온보딩, 계정 없이 시작, 소셜 로그인, 같은 계정 재로그인, 다른 계정 로그인, 로컬 기록 이어받기, 자동 인증 해제, 저장 방식별 로그아웃을 검토했습니다.

## 문제점

### [AUTH-01][P1] 로컬 모드 로그아웃 후 앱을 다시 켜면 이전 계정이 복원될 수 있음

- 조건: 서버 기록을 최초 다운로드한 계정으로 동기화를 끈 뒤 로그아웃하고, 온보딩에서 앱을 종료했다가 다시 실행합니다.
- 근거: [lib/features/auth/providers/auth_notifier.dart:501](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/auth/providers/auth_notifier.dart:501)은 기록 소유자를 standalone으로 바꾸고 `local_auth_user`와 standalone 활성 표시를 지우지만, `initial_*_synced_user_기존ID` 완료 키를 남깁니다. [lib/features/auth/data/local_auth_store.dart:45](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/auth/data/local_auth_store.dart:45)의 구형 계정 복원은 그 키에서 기존 계정을 다시 추정합니다. [lib/features/auth/data/local_auth_store.dart:166](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/auth/data/local_auth_store.dart:166)은 완료 키만으로 기록 사용을 허용하고, [lib/features/auth/providers/auth_notifier.dart:60](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/auth/providers/auth_notifier.dart:60)은 이를 `localOnly`로 복원합니다.
- 영향: 사용자가 로그아웃했는데도 메인 화면이 다시 열릴 수 있습니다. 책은 표시되지만 노트·독후감의 실제 소유자는 standalone이고 조회 소유자는 이전 계정이어서 기록이 사라진 것처럼 보일 수 있습니다. 토큰이 다시 유효해진다는 의미는 아닙니다.
- 재현 확인: 최초 동기화 이력이 있는 계정으로 동기화 끄기 → 로그아웃 → 온보딩에서 종료 → 재실행. 온보딩 유지 여부와 노트 소유자를 확인합니다.

### [AUTH-02][P2] 로컬 기록을 다른 계정에 이어받을 때 이전 계정의 server_id가 남음

- 조건: A 계정에서 내려받은 기록을 로컬 모드로 전환하고 로그아웃한 뒤, 계정 없이 이어 쓰다가 B 계정으로 로그인해 계정에 올리기를 선택합니다.
- 근거: [lib/features/auth/data/local_auth_store.dart:150](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/auth/data/local_auth_store.dart:150)은 `owner_user_id`만 바꿉니다. 책·노트·메모·독후감 등의 `server_id`와 기존 서버 관계는 그대로입니다. [lib/features/auth/providers/auth_notifier.dart:316](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/auth/providers/auth_notifier.dart:316)은 standalone 소유 기록을 새 계정에 채택하고, Import payload는 과거 `serverId`를 그대로 전송합니다.
- 영향: Import API의 기존 행 소유권 검사에 걸려 다른 계정으로 동기화를 켤 수 없습니다. 서버 문서대로라면 다른 계정 기록을 수정하는 보안 우회는 차단됩니다.
- 계약 근거: [../../api-doc/api-me-records-import-importId-items-post.md:107](/Users/hagulu/develop/service/BBBook/project/app/bbbook/../../api-doc/api-me-records-import-importId-items-post.md:107)의 `serverId` 소유권 규칙.

## 개선 제안

- AUTH-01: standalone 소유의 로컬 모드가 명시적으로 기록돼 있으면 과거 최초 동기화 완료 키로 계정을 추정하지 않도록 복원 우선순위를 정합니다. 로그아웃 트랜잭션에서 해당 복원 메타를 정리하는 방법도 검토할 수 있습니다. 기록·이미지 삭제로 해결하면 안 됩니다.
- AUTH-02: 기록의 원래 서버 소유자와 새 계정이 다를 때만 원격 바인딩을 새 계정용으로 재설정합니다. 같은 계정 복귀에 필요한 식별자를 무조건 지우거나, 이전 계정 서버 데이터를 자동 삭제하는 방식은 피합니다.

## 확인된 보호 장치

- refresh token은 secure storage에 저장하고 access token은 메모리에서 관리합니다.
- 401 갱신은 진행 중 Future를 공유하고 요청을 한 번 재시도합니다. multipart 재시도는 FormData를 복제합니다.
- 자동 인증 해제는 미전송 기록을 보존합니다. 다른 계정으로 일반 로그인할 때의 로컬 삭제에는 명시적 확인이 있습니다.
- 서버 모드 로그아웃 전 dirty 기록을 확인하고 재시도·로그아웃·취소를 구분합니다.

## 관련 문서

탈퇴 후 로컬 정리 누락은 [프로필 리뷰](../07-profile/20261028-124818-profile-settings-stats.md), 최초 다운로드 식별자 문제는 [최초 동기화 리뷰](../02-sync/20261028-124818-initial-download.md)를 참고하세요.
