# 리뷰 결과

직전 두 리뷰(`20260910-122111-settings-sync-inline-review.md`,
`20260910-123012-settings-sync-inline-rereview.md`) 이후의 수정분을 대상으로 한다.
수정은 두 갈래다 — (A) 컨트롤러 `AutoDispose` 제거 + `PopScope` 추가, (B) 서버 → 로컬 전환에서
기록 동기화·이미지 다운로드·검증 단계를 통째로 삭제.

## 요약
(A)는 직전 리뷰의 생명주기 지적 4건을 정확히 닫았지만, (B)는 "서버를 지우기 전에 로컬에 다
확보한다"는 이 기능의 안전 계약 자체를 제거해 서버에만 있는 이미지가 사용자 고지 없이
영구 삭제되고, 그 계약을 검증하던 테스트 5개가 실패 상태로 남아 있다.

## 문제점

- [문제] **서버에만 있는 이미지가 안내 없이 영구 삭제된다.** 서버 저장 모드에서 이미지는
  "열어 본 것부터" 지연 다운로드되므로 기기에 없는 서버 이미지가 정상적으로 존재한다
  (그 수를 세던 `countImagesPendingDownload()`가 이를 전제한다). 그런데 이제
  `local_storage_migration_service.dart:131-152`는 다운로드·검증 없이 곧바로
  `switchToLocalMode()` → `deleteServerRecords()`를 실행한다. 전환 후에는 서버 기록이 소프트
  삭제돼 그 이미지를 받을 경로가 사라진다. 확인 문구
  (`profile_settings_screen.dart:118-124`)도 기록만 언급하고 이미지는 한 글자도 없어, 사용자는
  메모 사진·독후감 이미지가 사라진다는 사실을 알 수 없다. 기록은 "다른 기기 변경사항을
  확인하라"고 사용자에게 책임을 넘길 수 있지만, 이미지는 **완전히 동기화된 기기에서도** 유실된다.

- [문제] **삭제된 안전 계약을 검증하던 테스트 5개가 실패한다.**
  `test/features/storage_mode/services/local_storage_migration_service_test.dart`는 6개 중 5개가
  깨진 채 남아 있다. 특히 "받지 못한 이미지가 남아 있으면 서버 데이터를 건드리지 않는다",
  "검증까지 통과하면 모드 전환을 먼저 기록한 뒤 서버 기록을 지운다"는 방금 제거된 계약을
  그대로 단언한다. 이 기능에서 테스트가 지키던 유일한 불변식이라 그대로 두면 안 된다.

- [문제] **전환 직후 결과 패널이 사라지거나, 반대쪽 결과 문구가 표시된다.**
  `_StorageModeCard`(`profile_settings_screen.dart:359-384`)는 여전히 `isLocal`로 볼 컨트롤러를
  고른다. 전환이 끝나면 `state = result`로 `stage`가 `completed`가 된 **직후**
  `ref.invalidate(storageModeProvider)`가 실행되고
  (`server_storage_migration_providers.dart:59,63` / `storage_mode_providers.dart:106,109`),
  `isLocal`이 뒤집히면서 카드가 반대쪽 컨트롤러를 보게 된다. 결과 문구는 한 프레임 남짓 보이고
  교체된다 — 직전 리뷰의 "결과가 즉시 사라진다"는 지적은 미해소다. (A)로 컨트롤러가 `Notifier`가
  되면서 여기에 한 가지가 더해졌다: 반대쪽 컨트롤러의 `stage`가 앱 수명 동안 남으므로,
  같은 세션에서 반대 방향 전환을 이미 한 번 끝냈다면 그 `completed`가 그대로 표시된다.
  - 로컬 → 서버(동기화 켜기): 로컬 모드였다는 것은 대개 같은 세션에서 껐다는 뜻이라,
    켠 직후 **"동기화를 껐어요"**가 뜨는 경우가 흔하다.
  - 서버 → 로컬(동기화 끄기): 서버 컨트롤러는 보통 `idle`이라 패널이 그냥 사라지고,
    같은 세션에서 켠 적이 있을 때만 "동기화를 켰어요"가 뜬다.

  (B)로 로컬 전환이 1초 안에 끝나게 되면서, 동기화를 끄면 스낵바도 결과 패널도 없이 상태 pill만
  바뀌는 사실상 무피드백 상태가 됐다.

- [문제] **진행 중인 동기화와 서버 삭제가 겹칠 창이 남았고, (B)로 오히려 잦아졌다.**
  `_migrationRunning` 가드는 되살아났지만 **이미 진행 중인 동기화를 취소하지는 않는다**. 각
  repository의 저장 모드 게이트는 `_runSync` 진입 시 1회만 검사되고
  (`bookshelf_repository.dart:79`), 응답 적용부는 모드를 재확인하지 않은 채 로컬 행을 지운다
  (`bookshelf_dao.dart:229-243`의 `reconcile`은 서버 응답에 없는 행을 `is_dirty = 0` 조건만으로
  삭제). 전에는 전환이 수 분 걸려 삭제가 맨 끝에 있었지만, 이제는 탭 직후 1초 안에
  `deleteServerRecords()`가 나간다 — "탭한 순간 백그라운드 동기화가 왕복 중"이 예외적인 꼬리가
  아니라 창의 전부가 됐다(앱 진입 직후 동기화가 도는 동안 설정에 들어가 끄는 흐름이 그대로 해당).

- [문제] **로그아웃·계정 전환 시 두 컨트롤러가 초기화되지 않는다(신규, (A)의 부작용).**
  `auth_notifier.dart:330-363`의 `_clearLocalBookshelf()`는 계정에 종속된 provider를 하나씩
  나열해 무효화하고, 주석(`:325-329`)이 그 이유를 명시한다. `AutoDispose`였을 때는 화면을
  벗어나며 스스로 폐기돼 이 목록에 없어도 됐지만, 이제 앱 수명 동안 살아 있으므로
  두 컨트롤러가 이 목록에서 빠진 것이 곧 누락이다. 로그아웃 후 다른 계정으로 로그인해 설정을
  열면 이전 계정의 `completed`/`failed` 패널이 그대로 보이고, `failed` 상태의 "다시 시도"는
  `_run()`이 `authNotifierProvider`에서 **새 계정의** id를 읽어 그 계정의 동기화를 끄는 동작으로
  이어진다.

- [문제] **첫 진행 문구가 사실과 다르고, 죽은 단계·필드가 남아 있다.**
  `run()`은 여전히 `stage: syncingRecords`로 시작해 그대로 emit하므로
  (`local_storage_migration_service.dart:122-130`), UI에 "기록을 내려받는 중"
  (`profile_settings_screen.dart:551`)이 잠깐 뜬다 — 이제 기록 동기화는 하지 않는다.
  `downloadingImages`·`verifying` 단계와 `imagesDone`/`imagesTotal`/`unavailableImages`/
  `imageProgress`는 어디서도 채워지지 않아 진행률 표시가 항상 불확정 막대로 남는다.

- [문제] **호출자가 사라진 코드가 그대로 남아 안전장치가 있는 것처럼 보인다.**
  `LocalStorageMigrationSteps`의 `syncAllRecords()`·`downloadAllImages()`·
  `countMissingLocalImages()`는 선언(`local_storage_migration_service.dart:13-23`)과 구현
  (`local_storage_migration_steps.dart:36,54,83`)이 모두 남았지만 호출자가 없다. 특히
  `countMissingLocalImages()`의 "0이어야 이전을 마칠 수 있다"는 주석은 더 이상 사실이 아니다.
  `localStorageMigrationPreviewProvider`와 `LocalStorageMigrationPreview`
  (`storage_mode_providers.dart:38-55`)도 확인 문구에서 빠지며 호출자가 0이 됐다.
  `flutter analyze`는 통과하므로(No issues found) 이들은 조용히 남는다.

- [문제] **클래스 주석이 코드와 어긋난다.** `local_storage_migration_service.dart:104`는 단계를
  1·2로 다시 매겼는데, 바로 아래 `:106-109`는 여전히 "4와 5의 순서를 바꾸면 안 된다"고 적혀
  있어 존재하지 않는 단계를 가리킨다.

- [유지] **도달할 수 없는 화면 2개와 사실과 다른 파일 인덱스.**
  `LocalStorageMigrationScreen`·`ServerStorageMigrationScreen`은 여전히 참조가 없다. 게다가 이제
  `local_storage_migration_screen.dart:109-128`은 없어진 이미지 다운로드·검증 단계를 진행
  단계로 그리고 있어, 살릴 경우 그대로는 쓸 수 없다. `docs/file-index.md:127`의
  "프로필 설정 화면에서 진입"도 그대로다.

## 해소 확인

- 전환 중 이탈로 마무리 처리가 스킵되던 문제 → 해소. 두 컨트롤러가 `Notifier`가 되어
  `_disposed` 가드가 제거됐고(`storage_mode_providers.dart:100-118`,
  `server_storage_migration_providers.dart:53-63`), 화면과 무관하게 무효화·sync version 증가가
  실행된다.
- 이중 전환 동시 실행 → 해소. 컨트롤러가 유지되므로 `_inFlight`와 `stage`가 살아남아
  `isSwitching`이 정확하다.
- 백그라운드 동기화 가드 무력화 → **부분 해소**. `background_record_sync_provider.dart:93-95`의
  `_migrationRunning`이 다시 실제 상태를 읽어 새 동기화가 시작되는 것은 막는다. 이미 진행 중인
  동기화가 남기는 창은 위 문제점 항목 참고 — 현재 남은 가장 큰 잔존 위험이다.
- `_retryServerCleanup`의 dispose된 `ref` 사용 → 해소(`storage_mode_providers.dart:78`).
- 전환 중 뒤로 가기 → `PopScope(canPop: !isSwitching)` 추가로 해소
  (`profile_settings_screen.dart:32-34, 37`).

## 개선 제안

- 이미지 유실 → 둘 중 하나를 택한다.
  1. 되돌리기: 이미지 다운로드·검증 단계를 복원하고 서버 삭제 전 확보를 보장한다. 원래 설계
     의도이며 테스트도 이 계약을 그대로 지킨다.
  2. 유지하되 고지: 전환을 즉시 끝내는 방향을 의도한 것이라면, 확인 문구에 유실될 이미지 수를
     넣는다. `localStorageMigrationPreviewProvider`가 쓰는
     `countImagesPendingDownload()`(메모 + 독후감)가 곧 "이 기기에 없어 삭제 후 되찾을 수 없는
     이미지 수"이므로, 그 값을 그대로 "이미지 N장은 이 기기에 없어 지금 끄면 되찾을 수
     없습니다"로 노출하면 된다(아래 죽은 코드 정리에서 이 provider만 남긴다). 함께 전환 전에
     받아둘 수단(예: "지금 모두 내려받기")을 제공한다. 지금처럼 이미지를 언급조차 하지 않는
     문구로는 동의를 받았다고 보기 어렵다.
- 실패 테스트 → 위 선택에 맞춰 정리한다. 1을 택하면 테스트는 그대로 통과한다. 2를 택하면
  이미지 관련 3개는 삭제하고, "모드 전환을 서버 삭제보다 먼저 기록한다"·"서버 삭제가 실패해도
  모드는 되돌리지 않는다"는 남은 불변식을 검증하도록 다시 쓴다. 실패한 채로 두지 않는다.
- 반대쪽 결과 문구 표시 → `_StorageModeCard`가 `isLocal`로 컨트롤러를 고르는 구조를 버리고 두
  컨트롤러를 모두 `watch`한 뒤 `stage != idle`인 쪽을 표시한다. 여기에 완료 시
  `AppSnackBar.success` + 패널을 닫고 `stage`를 `idle`로 되돌리는 "확인"을 붙이면, 결과가
  사라지지도 반대쪽이 뜨지도 않는다. `Notifier`로 바뀐 지금은 `idle` 복귀 수단이 특히 필요하다.
- 계정 전환 시 상태 잔존 → `auth_notifier.dart`의 `_clearLocalBookshelf()`에
  `ref.invalidate(localStorageMigrationControllerProvider)`와
  `ref.invalidate(serverStorageMigrationControllerProvider)`를 추가한다. 같은 함수의 다른
  항목들과 같은 이유이므로 주석 한 줄로 근거를 남긴다.
- 첫 단계 문구·죽은 단계 → `run()`의 시작 `stage`를 `switchingMode`로 바꾸고,
  `downloadingImages`·`verifying`과 `imagesDone`/`imagesTotal`/`unavailableImages`/
  `imageProgress`는 (1을 택하지 않는다면) enum·state에서 제거한다. 진행률이 항상 불확정이면
  `LinearProgressIndicator` 대신 짧은 문구만 두는 편이 정확하다.
- 죽은 코드 → `LocalStorageMigrationSteps`의 미사용 3개 메서드와 구현,
  `localStorageMigrationPreviewProvider`/`LocalStorageMigrationPreview`를 정리한다(2를 택해
  확인 문구에서 preview를 다시 쓴다면 그것만 남긴다).
- 클래스 주석 → `:106-109`의 "4와 5"를 새 번호(1과 2)에 맞추고, 삭제된 3단계 검증에 대한
  설명은 지운다.
- 죽은 화면·인덱스 → 인라인 UI가 대체라면 두 화면 파일을 삭제하고 `docs/file-index.md:115,127`
  항목도 함께 지운다. 남길 계획이면 최소한 `:127`의 "프로필 설정 화면에서 진입" 문구를 고친다.
- 동기화 타일의 조작 방식(직전 리뷰에서 이어짐) → `showCaret: false` + 상태 pill이라 읽기 전용
  표시처럼 보이는데 탭하면 표시된 상태의 **반대 방향** 전환이 시작된다
  (`profile_settings_screen.dart:389-398`). `Switch`나 명시적 동작 라벨로 바꾼다.
- 접근성(낮은 우선순위) → 진행률 `Semantics(label:, value:)` 부재, `_PolicyLink`의 탭 영역
  (12px `Text` 단독, 48dp 미달), `_ProfileCard`의 `excludeSemantics: true`로 닉네임·이메일 누락은
  직전 리뷰와 동일하게 남아 있다.
- `package_info_plus ^10.2.1`은 새로 추가된 네이티브 플러그인이라 `flutter analyze`로는
  iOS/Android 통합이 확인되지 않는다(이 리뷰에서 검증하지 않음) → 실제 빌드로 확인한다.
