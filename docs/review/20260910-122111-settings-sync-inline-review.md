# 리뷰 결과

## 요약
설정 화면 재구성과 앱 이름 변경 자체는 문제없으나, 저장 모드 전환을 전용 화면에서 설정 화면 안으로 옮기면서 전용 화면이 갖고 있던 "전환이 끝날 때까지 화면을 붙잡아 두는" 보호 장치가 사라져, 전환 도중 화면을 벗어나면 마무리 처리가 통째로 건너뛰어지고 완료·경고 안내도 사용자에게 도달하지 못한다.

## 문제점

- [문제] **전환 진행 중 설정 화면을 벗어나면 마무리 처리가 전부 스킵된다.** `localStorageMigrationControllerProvider` / `serverStorageMigrationControllerProvider`는 `AutoDisposeNotifierProvider`이고, 이번 변경 이후 실질적인 구독자는 `profile_settings_screen.dart:379`(또는 `:368`)의 `_StorageModeCard` 하나뿐이다. 그런데 새 설정 화면에는 `PopScope`가 없고 `_SettingsMenuTile`을 비활성화(`onTap: null`)할 뿐이라 뒤로 가기를 막지 못한다. 전환 중 뒤로 가기를 누르면 → 유일한 구독자 소멸 → autoDispose → `storage_mode_providers.dart:65`의 `_disposed = true` → 서비스는 계속 돌아 `switchToLocalMode()`·`deleteServerRecords()`까지 마치지만, `storage_mode_providers.dart:109`의 `if (_disposed) return;`에서 조기 반환되어 아래가 전부 실행되지 않는다.
  - `ref.invalidate(storageModeProvider)` — 설정 화면을 다시 열면 실제로는 로컬 모드인데 "동기화 켜짐"으로 표시된다.
  - `ref.invalidate(serverDeletePendingProvider)` — 서버 정리가 실패로 남아도 "서버 기록 정리가 남아 있습니다" 재시도 진입점이 뜨지 않는다.
  - `bookshelfSyncVersionProvider` 등 3종 증가 — 내려받은 기록이 서재·메모·독후감 목록에 반영되지 않는다.

  삭제된 전용 화면(`local_storage_migration_screen.dart:41`)의 `PopScope(canPop: completed || failed)`가 정확히 이 상황을 막고 있던 장치다.

- [문제] **위 상황에서 백그라운드 동기화 차단 가드까지 무력화된다.** `background_record_sync_provider.dart:93-95`의 `_migrationRunning`은 두 컨트롤러를 `ref.read`로 확인한다. 컨트롤러가 autoDispose된 뒤에는 `ref.read`가 새 인스턴스를 만들어 `stage == idle`을 돌려주므로 `isRunning`이 `false`가 되고, 실제로는 전환이 진행 중인데도 백그라운드 동기화가 함께 돌 수 있다. 특히 `syncingRecords`·`downloadingImages` 구간은 저장 모드가 아직 서버라 `background_record_sync_provider.dart:107`의 `isLocal()` 게이트에도 걸리지 않는다.

  다만 저장 모드 게이트 자체(`record_sync_providers.dart:63`, `background_record_sync_provider.dart:107`)는 provider가 아니라 `StorageModeStore`를 직접 읽으므로, `storageModeProvider`가 낡은 값으로 남는 것만으로 로컬 데이터가 손상되지는 않는다. 영향은 위 두 항목 범위에 그친다.

- [문제] **서버에서 더 이상 받을 수 없는 이미지 안내가 사라졌다.** `LocalStorageMigrationState.unavailableImages`는 "전환을 막지는 않지만 사용자에게 알려야 하는" 값인데(`local_storage_migration_service.dart:69-71`), 새 `_LocalMigrationProgress`(`profile_settings_screen.dart:547`)는 이 값을 전혀 표시하지 않는다. 삭제된 전용 화면 `local_storage_migration_screen.dart:135-152`에 있던 "이미지 N장은 서버에서 더 이상 받을 수 없어 옮기지 못했습니다" 안내가 대체 없이 없어져, 이미지 유실을 사용자가 알 방법이 없다.

- [문제] **완료·실패 결과가 표시되자마자 사라진다.** `_StorageModeCard`(`profile_settings_screen.dart:373`)는 `isLocal` 값에 따라 두 컨트롤러 중 하나만 `watch`하는데, `isLocal`은 전환이 끝나는 순간 `storageModeProvider` 무효화로 뒤집힌다. 로컬 전환 완료 → `isLocal`이 `true`로 바뀜 → 카드가 서버 컨트롤러(idle)를 보게 됨 → "동기화를 껐어요" 패널이 즉시 사라진다. 서버 전환도 대칭으로 같다. 전용 화면에 있던 완료 화면과 `AppSnackBar.success` 알림이 함께 없어져, 사용자는 상태 pill이 바뀐 것 외에 완료 확인을 받지 못한다.

  같은 구조 때문에, 로컬 전환이 서버 정리 단계에서 실패한 경우(모드는 이미 로컬)에도 `state.failureMessage`와 "다시 시도" 버튼이 표시되기 전에 사라진다. 다만 이 경로는 `serverDeletePendingProvider`가 true가 되어 `_MigrationNotice`("서버 기록 정리가 남아 있습니다")가 대체 안내 역할을 하므로, 사용자가 아무 안내도 못 받는 상태는 아니다.

- [문제] **`_retryServerCleanup`이 dispose된 `ref` 위에서 마무리된다(기존 문제).** 이 버튼이 보이는 조건은 `isLocal == true`이고, 그때 `_StorageModeCard`가 `watch`하는 것은 서버 컨트롤러다. 즉 `localStorageMigrationControllerProvider`에는 구독자가 없고, `profile_settings_screen.dart:137`의 `ref.read(...notifier)`는 구독을 만들지 않는다. DELETE 응답을 기다리는 동안 컨트롤러가 autoDispose되므로 `storage_mode_providers.dart:76-86`의 뒷부분이 이미 폐기된 `ref` 위에서 실행된다.
  - 확실한 결과: `storage_mode_providers.dart:80`의 `if (!_disposed) ref.invalidate(serverDeletePendingProvider)`가 건너뛰어져, "서버 기록을 정리했습니다" 스낵바는 뜨는데 "서버 기록 정리가 남아 있습니다" 알림은 그대로 남는다.
  - 더 나쁜 가능성: 바로 앞줄의 `ref.read(storageModeStoreProvider).markServerRecordsDeleted()`도 같은 `ref`를 탄다. 이 호출이 실패하면 `catch`가 `false`를 돌려주므로 DELETE는 성공했는데 "정리하지 못했습니다"가 뜨고, pending 플래그가 지워지지 않아 재시도가 항상 실패로 보고되는 상태가 굳어질 수 있다.

  이번 diff가 만든 문제는 아니지만, 이 diff가 해당 위젯을 `ConsumerWidget`으로 바꾸며 재구성한 자리다.

- [문제] **더 이상 도달할 수 없는 화면 2개가 남아 있고, 파일 인덱스가 사실과 다르다.** `LocalStorageMigrationScreen`·`ServerStorageMigrationScreen`은 어디에서도 참조되지 않는데(정의부와 자기 자신 내부 참조뿐), 이번 diff는 그 안의 문구까지 "동기화 켜기/끄기"로 수정했다. 또 `docs/file-index.md:127`은 여전히 서버 전환 화면을 "프로필 설정 화면에서 진입"이라고 적고 있다.

## 개선 제안

- 전환 중 이탈로 마무리 처리가 스킵되는 문제 → 두 가지를 함께 적용한다.
  1. `ProfileSettingsScreen`을 `PopScope`로 감싸 전환 중(`isSwitching`)에는 뒤로 가기를 막는다. 전용 화면이 하던 보호를 그대로 옮기는 최소 수정이다.
  2. 그것만으로는 탭 전환·앱 종료 같은 경로가 남으므로, 두 컨트롤러의 `AutoDisposeNotifierProvider`를 `NotifierProvider`로 바꾸거나, 실행 중에는 `ref.keepAlive()`로 링크를 유지하고 완료·실패 시 해제한다. 그러면 화면과 무관하게 `state = result` 이후의 무효화와 sync version 증가가 항상 실행되고, `background_record_sync_provider`의 `_migrationRunning` 가드도 다시 유효해진다.

- 완료·실패 결과가 즉시 사라지는 문제 → `_StorageModeCard`가 `isLocal`로 볼 컨트롤러를 고르는 구조를 바꾼다. 두 컨트롤러를 모두 `watch`하고 `stage != idle`인 쪽을 표시하면, 모드가 뒤집혀도 방금 끝난 전환의 결과가 계속 보인다. 여기에 전용 화면이 갖고 있던 완료 처리(`AppSnackBar.success` + 결과 패널을 닫는 "확인" 동작)를 더해, 사용자가 결과를 확인한 뒤 상태를 `idle`로 되돌리게 한다.

- `unavailableImages` 안내 소실 → `_LocalMigrationProgress`의 완료 분기에서 `state.unavailableImages > 0`이면 "이미지 N장은 서버에서 더 이상 받을 수 없어 옮기지 못했습니다"를 함께 노출한다. 결과 패널이 유지되도록 위 항목을 먼저 고쳐야 실제로 보인다.

- `_retryServerCleanup`의 dispose된 `ref` 사용 → 두 가지를 함께 고쳐야 한다. 호출부에서 `invalidate`만 챙기면 안내 잔존은 해결되지만 `markServerRecordsDeleted()`는 여전히 폐기된 `ref`를 타고 나간다.
  1. `retryServerCleanup()` 진입 시 `ref.keepAlive()`로 링크를 유지해 작업이 끝날 때까지 컨트롤러를 살려 두거나, 이 정리 작업 자체를 autoDispose 컨트롤러 밖(예: 별도 서비스나 `NotifierProvider`)으로 옮긴다.
  2. 안내 갱신은 `retryServerCleanup()`이 `bool`을 돌려주므로 컨트롤러 내부의 `ref.invalidate`에 기대지 말고, 호출부에서 성공 시 `ref.invalidate(serverDeletePendingProvider)`를 직접 실행한다. 화면의 `WidgetRef`는 autoDispose 대상이 아니라 확실히 동작한다.

- 죽은 화면과 인덱스 불일치 → 다음 중 하나로 정리한다.
  - 삭제: `local_storage_migration_screen.dart`·`server_storage_migration_screen.dart`를 제거하고 `docs/file-index.md:115,127` 항목도 함께 지운다. 인라인 UI가 이 둘을 완전히 대체한다면 이쪽이 깔끔하다.
  - 유지: 되살릴 계획이 있다면 최소한 `docs/file-index.md:127`의 "프로필 설정 화면에서 진입" 문구를 현재 사실(진입점 없음)에 맞게 고친다.

- 접근성(모두 낮은 우선순위)
  - 진행률 → 전용 화면 `local_storage_migration_screen.dart:85-89`에 있던 `Semantics(label: '이미지 내려받기 진행률', value: 'N / M')`가 새 `_MigrationProgress`의 `LinearProgressIndicator`에는 없다. 동일하게 감싸 준다.
  - `_PolicyLink`(기존 코드 이동) → 12px `Text`만 탭 대상이라 유효 높이가 15px 남짓이다. `MinimumTapTargetGuideline`(48dp)을 만족하도록 `Padding`이나 `SizedBox`로 탭 영역을 넓히고 `Semantics(link: true)`를 붙인다.
  - `_ProfileCard`(기존 동작 유지) → `excludeSemantics: true`에 `label: '프로필 수정'`만 있어 닉네임·이메일이 스크린 리더에 읽히지 않는다. `label: '$nickname, 프로필 수정'` 형태로 본문 정보를 레이블에 포함한다.
