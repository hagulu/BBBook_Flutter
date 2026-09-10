# 리뷰 결과

대상 diff는 직전 리뷰(`docs/review/20260910-122111-settings-sync-inline-review.md`)와 동일하다
(소스 최종 수정 12:12, 직전 리뷰 작성 12:24 — 이후 코드 변경 없음). 따라서 항목을
다시 도출하지 않고 **유지 / 해소 / 신규**로 판정한다. `flutter analyze`는 통과한다(No issues found).

## 요약
직전 리뷰의 6개 지적은 전부 그대로 유지되며, 그중 첫 번째(전환 중 이탈 시 컨트롤러 autoDispose)는
직전 리뷰가 "로컬 데이터가 손상되지는 않는다"고 범위를 좁혀 잡은 것보다 실제 위험이 크다 —
두 번째 전환을 동시에 시작할 수 있고, 백그라운드 동기화 차단이 풀리면서 서비스가 순서로
막으려던 "서버 삭제 직후 동기화가 로컬 원본을 지우는" 창이 열린다.

## 문제점

- [유지] **전환 진행 중 설정 화면을 벗어나면 마무리 처리가 전부 스킵된다.** 코드 확인 결과
  `_StorageModeCard`(`profile_settings_screen.dart:364`)가 두 컨트롤러의 유일한 구독자이고,
  새 설정 화면에는 `PopScope`가 없다. 뒤로 가기 → autoDispose →
  `storage_mode_providers.dart:109`의 `if (_disposed) return;`에서 조기 반환 →
  `storageModeProvider`·`serverDeletePendingProvider` 무효화와 sync version 3종 증가가 모두 유실.
  삭제 대상이 아니었던 전용 화면의 `PopScope(canPop: completed || failed)`
  (`local_storage_migration_screen.dart:41`)가 이 자리를 지키고 있었다.

- [신규] **위 상태에서 같은 전환을 두 번 동시에 돌릴 수 있다.** 컨트롤러가 사라져도
  `LocalStorageMigrationService`는 계속 돈다. 그런데 `storageModeProvider`는 autoDispose가
  아니고 무효화도 스킵됐으므로 여전히 `server`를 캐시하고 있다. 사용자가 설정에 다시 들어오면
  → 새 컨트롤러(`_inFlight == null`, `stage == idle`) → `isSwitching == false` → 타일이 다시
  활성화되고 "동기화 끄기"를 그대로 제안 → 탭하면 두 번째 `LocalStorageMigrationService`가
  첫 번째와 나란히 실행된다. 이 서비스의 안전성은 전적으로 `1 동기화 → 2 이미지 확보 →
  3 검증 → 4 모드 전환 → 5 서버 삭제` 순서(`local_storage_migration_service.dart:101-115`)에
  기대고 있는데, 두 실행이 겹치면 한쪽이 5(서버 삭제)에 있는 동안 다른 쪽이 1(서버 동기화)에
  있을 수 있어 그 전제가 깨진다.

- [신규/직전 리뷰 수정] **백그라운드 동기화 차단이 풀리는 것은 표시 문제로 끝나지 않는다.**
  직전 리뷰는 "저장 모드 게이트가 `StorageModeStore`를 직접 읽으므로 로컬 데이터가 손상되지는
  않는다"고 범위를 좁혔지만, 코드를 따라가 보면 그렇지 않다.
  - 게이트는 **동기화 시작 시점에 한 번만** 검사된다(`bookshelf_repository.dart:79`의 `_runSync`
    첫 줄, `background_record_sync_provider.dart:107`). 이후 중간 재검사
    (`bookshelf_repository.dart:101,120`)는 `sessionGeneration`만 보고 저장 모드는 다시 읽지 않는다.
  - 응답 적용 경로도 모드를 재확인하지 않고 곧바로 로컬 행을 지운다 —
    `bookshelf_dao.dart:229-243`의 `reconcile`은 서버 응답에 없는 행을 `is_dirty = 0` 조건만으로
    삭제하고, `applyChanges`(`bookshelf_dao.dart:256-`)는 `deletedUserBookIds`를 그대로 삭제한다.
    전환 직전 동기화로 대부분의 로컬 행은 `is_dirty = 0`이므로 보호받지 못한다.

  즉 게이트를 통과한 동기화가 네트워크 왕복 중인 사이 전환이 `switchToLocalMode()` →
  `deleteServerRecords()`까지 나아가면, 돌아온 응답이 "서버에서 사라진 기록"으로 해석돼 로컬
  원본이 지워질 수 있다. `local_storage_migration_service.dart:107-110` 주석이 4·5 순서로 막으려는
  바로 그 시나리오이며, 순서 규칙은 **전환 중 다른 동기화가 돌지 않는다**는 전제 위에서만 성립한다.
  그 전제를 지키는 것이 `background_record_sync_provider.dart:93-95`의 `_migrationRunning`인데,
  autoDispose 이후 `ref.read`가 새 인스턴스의 `idle`을 돌려주면서 가드가 무력화된다. 전환이 수 분
  걸리면 15초 주기 스케줄이 그 창을 여러 번 노린다.

- [유지] **서버에서 더 이상 받을 수 없는 이미지 안내가 사라졌다.**
  `LocalStorageMigrationState.unavailableImages`(`local_storage_migration_service.dart:71`,
  `:140`에서 채워짐)를 새 `_LocalMigrationProgress`(`profile_settings_screen.dart:544`)가 전혀
  읽지 않는다. 전용 화면 `local_storage_migration_screen.dart:135-152`의
  "이미지 N장은 서버에서 더 이상 받을 수 없어 옮기지 못했습니다" 안내가 대체 없이 없어졌다.

- [유지] **완료·실패 결과가 표시되자마자 사라진다.** `_StorageModeCard`가 `isLocal`로 볼 컨트롤러를
  고르는데(`profile_settings_screen.dart:367-389`), 전환 완료 시
  `storage_mode_providers.dart:114`의 `ref.invalidate(storageModeProvider)`로 `isLocal`이 뒤집혀
  방금 끝난 쪽이 아니라 반대쪽(=idle) 컨트롤러를 보게 된다. 결과 패널이 즉시 사라지고, 전용 화면에
  있던 완료 확인(`AppSnackBar.success` + "완료" 버튼)도 대체 없이 없어져 사용자가 받는 피드백은
  상태 pill 변화뿐이다.

- [유지] **`_retryServerCleanup`이 dispose된 `ref` 위에서 마무리된다(기존 문제).** 이 버튼이 보이는
  조건은 `isLocal == true`이고 그때 카드가 watch하는 것은 서버 컨트롤러다. 즉
  `localStorageMigrationControllerProvider`에는 구독자가 없고
  `profile_settings_screen.dart:136-138`의 `ref.read(...notifier)`는 구독을 만들지 않으므로,
  DELETE 응답을 기다리는 사이 컨트롤러가 autoDispose된다. 결과적으로
  `storage_mode_providers.dart:80`의 `if (!_disposed) ref.invalidate(serverDeletePendingProvider)`가
  건너뛰어져 "정리했습니다" 스낵바와 "정리가 남아 있습니다" 안내가 동시에 보인다. 바로 앞
  `:79`의 `markServerRecordsDeleted()`도 같은 `ref`를 타므로 실패 시 pending 플래그가 영구히
  남을 수 있다.

- [유지] **도달할 수 없는 화면 2개와 사실과 다른 파일 인덱스.** `LocalStorageMigrationScreen`·
  `ServerStorageMigrationScreen`은 정의부 외 참조가 없다(전체 검색으로 확인). 그런데 이번 diff는
  그 안의 문구까지 "동기화 켜기/끄기"로 고쳤다. `docs/file-index.md:127`은 여전히 서버 전환 화면을
  "프로필 설정 화면에서 진입"이라고 적고 있다.

## 개선 제안

- 전환 중 이탈로 마무리가 스킵되고 이중 실행·동기화 창까지 열리는 문제 → 아래를 함께 적용한다.
  1. 두 컨트롤러를 `AutoDisposeNotifierProvider` → `NotifierProvider`로 바꾸거나, `start()` 진입 시
     `ref.keepAlive()`로 링크를 잡고 완료·실패 후 해제한다. 화면과 무관하게 `state = result` 이후
     무효화·sync version 증가가 실행되고, `_migrationRunning` 가드와 `_inFlight` 중복 방지가
     함께 되살아난다(신규 지적 2건이 여기서 같이 닫힌다).
  2. 그 위에 `ProfileSettingsScreen`을 `PopScope(canPop: !isSwitching)`로 감싸 전환 중 이탈 자체를
     막는다. 전용 화면이 하던 보호를 옮기는 최소 수정이다.

- 결과가 즉시 사라지는 문제 → `_StorageModeCard`가 두 컨트롤러를 모두 `watch`하고 `stage != idle`인
  쪽을 표시하도록 바꾼다. 모드가 뒤집혀도 방금 끝난 전환의 결과가 남는다. 여기에
  `AppSnackBar.success` + 결과 패널을 닫는 "확인"을 더해 사용자가 확인한 뒤 `idle`로 되돌린다.

- `unavailableImages` 안내 소실 → `_LocalMigrationProgress`의 완료 분기에서 `unavailableImages > 0`이면
  "이미지 N장은 서버에서 더 이상 받을 수 없어 옮기지 못했습니다"를 함께 노출한다. 위 항목을 먼저
  고쳐야 실제로 보인다.

- `_retryServerCleanup` → 정리 작업에 `ref.keepAlive()`를 걸거나 autoDispose 컨트롤러 밖으로 옮기고,
  안내 갱신은 `retryServerCleanup()`의 반환값을 받아 **호출부의 `WidgetRef`에서**
  `ref.invalidate(serverDeletePendingProvider)`를 직접 실행한다.

- 죽은 화면·인덱스 → 인라인 UI가 완전한 대체라면 두 화면 파일을 삭제하고
  `docs/file-index.md:115,127` 항목도 함께 지운다. 남길 계획이면 최소한 `:127`의
  "프로필 설정 화면에서 진입" 문구를 현재 사실(진입점 없음)에 맞게 고친다.

- 동기화 타일의 조작 방식(신규) → `_SettingsMenuTile`을 `showCaret: false` + 상태 pill로 렌더링해
  "읽기 전용 상태 표시"처럼 보이는데, 탭하면 **표시된 상태의 반대 방향**으로 전환이 시작된다
  (`profile_settings_screen.dart:394-404`). 전환 중에는 `onTap: null`이 되지만 시각적으로는 동일하다.
  일반적인 설정 화면 관례대로 `Switch`(또는 명시적 동작 라벨)로 바꾸고, 실행 중에는 비활성 상태가
  보이게 한다.

- 접근성(낮은 우선순위)
  - 진행률 → 전용 화면 `local_storage_migration_screen.dart:85-89`에 있던
    `Semantics(label: '이미지 내려받기 진행률', value: 'N / M')`가 새 `_MigrationProgress`의
    `LinearProgressIndicator`에는 없다.
  - `_PolicyLink`(기존 코드 이동) → 12px `Text`만 탭 대상이라 유효 높이가 15px 남짓이다.
    `MinimumTapTargetGuideline`(48dp)을 만족하도록 탭 영역을 넓히고 `Semantics(link: true)`를 붙인다.
  - `_ProfileCard`(기존 동작 유지) → `excludeSemantics: true` + `label: '프로필 수정'`이라 닉네임·이메일이
    읽히지 않는다. `label: '$nickname, 프로필 수정'` 형태로 본문 정보를 포함한다.

- `package_info_plus ^10.2.1`은 이번에 새로 추가된 네이티브 플러그인이라 `flutter analyze`로는
  iOS/Android 통합이 확인되지 않는다(이 리뷰에서 검증하지 않음) → 실제 빌드로 한 번 확인한다.
