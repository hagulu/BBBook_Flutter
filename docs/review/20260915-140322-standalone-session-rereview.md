# 리뷰 결과

## 요약
- 계정 없이 사용하는 기본 흐름은 연결됐지만, 회원 탈퇴의 로컬 데이터 삭제 회귀와 계정 전환 동의·소유권 메타데이터 처리에 출시 전 해결해야 할 문제가 남아 있습니다.

## 문제점
- [P1] 로컬 저장 모드에서 회원 탈퇴해도 기기의 기록과 사진이 남습니다. `ProfileEditScreen._deleteAccount()`는 “모든 독서 기록과 데이터가 영구적으로 삭제”된다고 확인받은 뒤 서버 탈퇴 성공 시 일반 `logout()`을 호출합니다(`lib/features/profile/screens/profile_edit_screen.dart:212-231`). 그러나 변경된 `AuthNotifier.logout()`은 로컬 저장 모드이면 `_detachAccountFromRecords()`로 소유자만 `standalone`으로 바꾸고 기록·이미지를 보존합니다(`lib/features/auth/providers/auth_notifier.dart:418-447,461-505`). 사용자는 탈퇴 뒤 온보딩의 “로그인 없이 사용하기”로 다시 들어가 삭제했다고 생각한 기록을 그대로 볼 수 있어, 명시적인 영구 삭제 약속과 개인정보 삭제 기대를 위반합니다.
- [P1] 기록 처리 선택 팝업을 시스템 뒤로 가기나 바깥 영역 탭으로 닫아도 로그인과 기록 소유권 이전이 계속됩니다. `AppConfirm.show()`는 취소 버튼뿐 아니라 다이얼로그 dismiss도 모두 `false`로 합칩니다(`lib/shared/widgets/app_confirm.dart:21-43`). 그런데 `_askStandaloneRecordAction()`은 그 `false`를 취소가 아니라 `keepOnDevice`라는 유효한 선택으로 변환합니다(`lib/features/auth/widgets/social_login_section.dart:103-119`). 따라서 사용자가 두 선택 모두 하지 않고 팝업을 닫아도 `_adoptLocalRecordsForLogin()`의 `action == null` 중단 조건에 도달하지 않고 새 계정으로 기록을 넘깁니다(`lib/features/auth/providers/auth_notifier.dart:314-329`).
- [P1] 로컬 계정에서 로그아웃해 standalone으로 바꿀 때 이전 계정에 묶인 서버 메타데이터를 안전하게 승계하지 못합니다. 소유자 전환은 `book_note`/`book_reflection.owner_user_id`만 바꾸고(`lib/features/auth/data/local_auth_store.dart:125-154`), 책·노트·메모·독후감의 기존 `serverId`는 그대로 남습니다. 이후 다른 계정으로 로그인해 “계정에 올리기”를 고르면 Import payload가 이 ID들을 새 계정 요청에 그대로 싣지만(`lib/features/server_storage_migration/data/record_import_payload_builder.dart:22-94`), API 규격은 `serverId`가 로그인 사용자 소유인지 검증하므로 다른 계정의 ID는 소유권 오류로 전체 Import를 실패시킵니다(`../../api-doc/api-me-records-import-importId-items-post.md:107,283-284`). 동시에 `switchToStandalone()`은 이전 계정의 `server_delete_pending`도 무조건 버려(`lib/features/storage_mode/data/storage_mode_store.dart:81-99`), 같은 계정으로 돌아와도 실패했던 서버 정리를 재시도할 수 없습니다.
- [P1] 소유권 변경을 SQLite 트랜잭션으로 묶은 뒤에도 로그인 전환 전체에는 실패 시 불일치 구간이 남아 있습니다. 기록이 있는 경우 `_adoptLocalRecordsForLogin()`이 먼저 기록 소유자·저장 모드·standalone 표시를 바꾼 뒤, 별도 작업으로 로컬 사용자와 refresh token을 저장하고 마지막에만 메모리 상태를 로그인으로 전환합니다(`lib/features/auth/providers/auth_notifier.dart:259-275,306-334`). `saveUser()`나 `saveSession()`이 실패하면 메모리 상태는 여전히 `standalone`이라 새 계정 id로 이미 바뀐 노트·독후감이 즉시 보이지 않고, 이후 작성분은 다시 sentinel 소유자로 섞일 수 있습니다. 기록이 없는 분기도 `resetToServer()`와 `endStandaloneSession()`을 별도 커밋해(`lib/features/auth/providers/auth_notifier.dart:307-312`), 두 작업 사이 종료 시 다음 실행은 standalone 상태인데 저장 모드는 서버인 조합으로 복원됩니다.

## 개선 제안
- 회원 탈퇴 후 로컬 기록 보존 → 탈퇴 경로는 일반 로그아웃과 분리해 저장 모드와 무관하게 `BookshelfDatabase.clearAll()` 및 이미지 저장소 정리를 보장하고, 완료된 뒤에만 미인증 상태로 전환합니다.
- 두 선택과 dismiss의 혼동 → 이 팝업은 `StandaloneRecordAction?`을 직접 반환하는 선택 다이얼로그로 만들고, 뒤로 가기·바깥 탭은 `null`로 반환해 로그인을 중단합니다. 공통 Confirm을 유지한다면 해당 팝업만 dismiss를 막고 별도의 명시적 취소 동작을 제공합니다.
- 이전 계정의 서버 메타데이터 승계 → 계정을 떼어낼 때 원래 계정 id와 서버 정리 보류 상태를 별도 provenance로 보존합니다. 같은 계정 재로그인에는 기존 ID와 보류 작업을 이어 주고, 다른 계정으로 넘길 때는 모든 서버 ID·동기화 기준값·계정 전용 공개 상태를 새 로컬 기록 기준으로 정규화한 뒤 Import하거나, 지원하지 않는다면 다른 계정 업로드를 명확히 차단합니다.
- 로그인 전환의 부분 커밋 → 새 세션 저장과 로컬 사용자 저장까지 성공한 뒤 소유권을 커밋하거나, 전환 저널과 보상 롤백을 두어 어느 단계에서 실패해도 standalone 또는 로그인 상태 중 하나로만 복구되게 합니다. 빈 기록 분기의 저장 모드 초기화와 standalone 표시 삭제도 같은 DB 트랜잭션으로 묶고, 각 단계 실패 테스트를 추가합니다.

---

`flutter analyze`를 실행했습니다. 프로젝트 지침에 따라 테스트와 앱 실행은 수행하지 않았습니다.
