# 리뷰 결과

## 요약
- 미커밋 변경(외부 기록 가져오기 책 선택·덮어쓰기, 복구 메모 정리, Import 로그 보강)에서 사용자 피드백 소실 1건, 이탈 불가 1건, 검증 없는 사용자 데이터 삭제 1건, 덮어쓰기 고지 누락 1건을 포함해 12건을 확인했다. `flutter analyze`는 통과했다.
- 코드와 `../../api-doc/api-me-records-import-importId-items-post.md`를 대조한 정적 리뷰다. 앱 실행과 테스트 실행은 하지 않았고 구현 코드도 수정하지 않았다.
- `docs/review/20260910-201039-external-record-import-review.md`에서 지적한 3건(ISBN 덮어쓰기 무고지, 동시 Import 충돌, CSV 식별자 충돌)은 이번 변경으로 모두 처리됐다. 아래는 그 후속 구현에 대한 새 지적이다.

## 문제점

- [P1 문제] 가져오기 성공/부분 실패 메시지가 사용자에게 한 번도 표시되지 않는다.
  - 위치: `lib/features/external_record_import/screens/external_import_screen.dart:22`, `:76`, `lib/features/external_record_import/providers/external_import_providers.dart:362`.
  - `startImport()`는 성공 시 `null`을 반환하므로 `onImport`의 `AppAlert`가 뜨지 않는다. 그 사이 컨트롤러는 `state.message`에 `'N권의 기록을 가져왔어요.'`를 넣지만, `completed` 분기는 `SizedBox.shrink()`만 그리고 같은 프레임의 `ref.listen`이 화면을 pop한다. 결과적으로 완료 안내가 어디에도 나오지 않는다.
  - 더 중요한 건 실패 쪽이다. 사후 동기화가 깨져 `refreshed == false`가 되면 메시지가 `'기록은 가져왔지만 목록 새로고침이 필요해요.'`로 바뀌는데, 이 경고 역시 같은 경로로 버려진다. 사용자는 책장이 비어 보이는 이유를 알 수 없다.
  - CLAUDE.md의 「사용자 안내/성공/실패/경고는 `AppSnackBar`」 규칙과도 어긋난다.

- [P1 문제] 분석·가져오기가 진행되는 동안 화면을 빠져나갈 수단이 완전히 사라졌다.
  - 위치: `lib/features/external_record_import/screens/external_import_screen.dart:43`, `lib/shared/widgets/app_loading.dart:81`.
  - `AppLoadingOverlay`가 `body`만 감싸던 것에서 `Scaffold` 전체를 감싸도록 바뀌었다. 이 위젯은 `Positioned.fill(AbsorbPointer(...))`라서 이제 AppBar의 뒤로가기 버튼까지 입력을 흡수한다.
  - `PopScope(canPop: false)`는 시스템 뒤로가기 제스처만 막고 AppBar가 호출하는 `Navigator.pop()`은 막지 않는다. 즉 변경 전에는 AppBar를 통한 탈출 경로가 있었고, 이번 변경으로 그게 없어졌다.
  - 가져오기 구간은 사전 동기화 4회(책장 2회·노트·독후감·태그) → 청크 업로드 → 사후 동기화 최대 6회로 길다. 네트워크가 멈추거나 서버 응답이 지연되면 사용자는 앱을 강제 종료하는 수밖에 없다.

- [P1 문제] 서버 응답만 근거로 사용자 노트·메모를 영구 삭제하는 로직이 provider에 있고 테스트가 없다.
  - 위치: `lib/features/external_record_import/providers/external_import_providers.dart:459`.
  - `_removeRestoredBookMemos()`는 복구된 책의 노트 중 `result.importedNoteServerIds`에 없는 것을 `deleteNote()`로, 메모 중 `importedNoteMemoServerIds`에 없는 것을 `deleteNoteMemo()`로 지운다. 두 집합은 `/items` 응답에서만 만들어진다. 응답 배열이 기대와 어긋나면 `_collectChunkMappings()`의 길이 검증에서 막히지만, "이 serverId는 이번 Import 산출물이 아니다 → 지운다"는 판정 자체는 아무 데서도 검증되지 않는다.
  - 삭제는 로컬 tombstone + 서버 push까지 이어지므로 되돌릴 수 없다. 인접한 덮어쓰기 경로(`external_import_snapshot_builder_test.dart`)에는 테스트가 추가됐는데, 파괴적인 이쪽 경로만 비어 있다.
  - CLAUDE.md의 「screen은 얇게 유지하고 로직은 model/service로 분리」 기준에서도 provider가 아니라 service에 있어야 할 흐름이다. `startImport()`는 현재 200줄 가까이 되며 사전 동기화·충돌 재확인·Import 실행·사후 정리·사후 동기화를 모두 직접 조율한다.

- [P1 문제] 덮어쓰기 확인 다이얼로그가 실제 초기화 범위를 다 알리지 않고, 표지는 사실과 다르게 알린다.
  - 위치: `lib/features/external_record_import/screens/external_import_screen.dart:88`, `lib/features/external_record_import/services/external_import_snapshot_builder.dart:44`.
  - api-doc 136행: 「그 외 ISBN13 또는 `serverId`로 찾은 활성 책은 표지(`coverImageUrl`)를 보존하고, 나머지 필드는 요청 값으로 대체한다.」 덮어쓰기용 `BookItem`은 `displayCategoryId`를 채우지 않으므로 `bookToImportJson()`이 `null`을 보내고 **기존 카테고리가 초기화된다**. 다이얼로그의 「명작, 난이도, 대출 정보 등」에는 카테고리가 없다.
  - 같은 문서 136행은 「요청 값으로 대체하는 경우 `displayTotalPages`를 생략하거나 `null`로 보내면 기존 override도 삭제된다」고 명시한다. 빌더는 비전자책이면 `displayTotalPages: null`을 보내므로 사용자가 직접 맞춰 둔 총 페이지 override가 사라진다.
  - 그 밖에 `wantToReread`, `platformName`, `discoverySource`도 초기화 대상인데 고지 문구에 없다.
  - 반대로 표지는 서버가 보존하므로 **바뀌지 않는다**. 「책 정보와 … 가져오는 기록으로 바뀝니다」는 표지도 교체된다는 인상을 준다. `external_import_snapshot_builder.dart:80`이 덮어쓰기 때도 `covers`를 채우지만 서버가 무시하므로 실제 효과가 없다.
  - 파괴적 동작에 대한 동의를 받는 화면이므로, 고지 내용과 실제 동작이 어긋나는 것 자체가 문제다.

- [P2 문제] 변경된 3개 파일만 `debugPrint`로 갈아타 로그 방식이 갈렸고, 릴리즈 빌드에도 그대로 출력된다.
  - 위치: `lib/features/external_record_import/providers/external_import_providers.dart:135`, `lib/features/external_record_import/services/external_record_import_service.dart:105`, `lib/features/server_storage_migration/data/record_import_api.dart:19`.
  - 나머지 32개 파일은 여전히 `developer.log`를 쓴다. 같은 Import 흐름 안의 `external_import_share_coordinator.dart`, `bookshelf_repository.dart`도 `developer.log`라 한 흐름의 로그가 두 채널로 나뉜다.
  - `debugPrint`/`debugPrintStack`은 이름과 달리 릴리즈에서도 출력된다. 지금 찍는 값에는 `userId`, 서버가 내려준 원문 메시지, 전체 스택 트레이스가 포함돼 기기 로그에 남는다. `exception-log` 스킬의 「민감 정보 기록 금지」와 충돌한다.
  - `debugPrint`의 기본 구현은 1KB/초 스로틀이라 스택 덤프가 큐에 밀리면 이후 로그와 순서가 뒤바뀐다. 장애 분석용 로그를 강화하려는 변경 의도와 반대로 작용한다.

- [P2 문제] 시작 로그가 즉시 실패하는 경로에서도 `result=SUCCESS`로 남는다.
  - 위치: `lib/features/external_record_import/providers/external_import_providers.dart:211`.
  - `'[외부 기록 가져오기 시작] … result=SUCCESS'`를 찍은 직후 218~221행에서 저장 모드가 로컬이면 그대로 반환한다. 실제로는 한 건도 가져오지 않았는데 로그만 성공으로 남아, 로그로 흐름을 재구성할 때 어긋난다.

- [P2 문제] 사용자 메시지 분기가 기본 문구 리터럴을 센티널로 비교한다.
  - 위치: `lib/features/external_record_import/services/external_record_import_service.dart:297`, `lib/features/server_storage_migration/data/record_import_api.dart:189`.
  - `_userMessage()`는 `error.message != '가져오기 요청 처리 중 오류가 발생했습니다.'`로 "서버가 준 메시지인지"를 판단한다. 서버 메시지를 그대로 보여주겠다는 결정 자체(테스트 `'서버가 전달한 가져오기 실패 사유를 사용자에게 보존한다'`)는 명시적이지만, 판단 근거가 다른 레이어의 문자열과 정확히 일치하는지에 달려 있다. 어느 한쪽 문구만 고쳐도 404/410 전용 안내가 조용히 사라지거나 서버 원문이 그대로 노출되는 쪽으로 바뀐다.

- [P2 문제] 가져오기 직후 계정 전체 기록을 최대 두 번 다시 내려받는다.
  - 위치: `lib/features/external_record_import/providers/external_import_providers.dart:332`, `:342`, `lib/features/book_note/data/book_note_repository.dart:343`.
  - `forceFullSync`는 `_fullSync()`로 직행하고, `_fullSync()`는 `/api/me/records`로 계정의 모든 책·노트·메모를 받아온다. 첫 호출은 항상 실행되고, `_removeRestoredBookMemos()`가 뭔가 지우면 두 번째까지 실행된다. 각 호출 앞에 `pushAllDirty()`도 붙는다.
  - 기록이 많은 사용자에게는 가져오기 자체보다 뒷정리가 더 오래 걸릴 수 있고, 앞의 "이탈 불가" 문제와 겹치면 체감이 크게 나빠진다.

- [P2 문제] 책 선택 목록이 가상화되지 않는다.
  - 위치: `lib/features/external_record_import/screens/external_import_screen.dart:152`, `:206`.
  - `SingleChildScrollView` 안의 `ListView.separated`에 `shrinkWrap: true`, `physics: NeverScrollableScrollPhysics()`를 줬다. 화면 밖 항목까지 전부 빌드·레이아웃된다. 북모리 백업은 수백~수천 권이 나올 수 있는 입력이고, 그만큼의 `_BookSelectionTile`이 매 상태 변경(체크 하나 토글)마다 다시 빌드된다.

- [P2 문제] 실패가 아닌 안내까지 「가져오지 못했어요」 Alert으로 뜬다.
  - 위치: `lib/features/external_record_import/screens/external_import_screen.dart:104`, `lib/features/external_record_import/providers/external_import_providers.dart:194`, `:293`.
  - `startImport()`는 `'가져올 책을 한 권 이상 선택해 주세요.'`, `'기존 책이 새로 확인되어 선택에서 제외했어요. 목록을 확인해 주세요.'`도 같은 반환 채널로 돌려준다. 후자는 정상적인 보호 동작이고 사용자는 목록을 다시 확인하면 되는데, 실패 제목의 모달 Alert이 붙는다.

- [P3 문제] 체크박스의 시맨틱스와 터치 영역이 규격에 못 미친다.
  - 위치: `lib/features/external_record_import/screens/external_import_screen.dart:290`, `:296`.
  - `IgnorePointer(child: Checkbox(onChanged: (_) {}))` 구조라 실제 조작은 `InkWell`이 받는다. 스크린 리더에는 체크박스와 탭 가능한 영역이 따로 읽히고, `onChanged`가 빈 함수라 상태 변경 액션이 체크박스 쪽에는 연결돼 있지 않다.
  - `materialTapTargetSize: MaterialTapTargetSize.shrinkWrap`에 상하 패딩 9를 쓰므로, 제목이 한 줄인 항목은 타일 높이가 48dp를 밑돈다.

- [P3 문제] feature가 app 레이어를 역참조한다.
  - 위치: `lib/features/external_record_import/screens/external_import_screen.dart:5`, `lib/app/main_shell.dart:19`.
  - `mainShellTabIndexProvider`가 `lib/app/main_shell.dart`에 선언되고 feature 화면이 그 파일을 import해 값을 바꾼다. `structure` 스킬 기준으로 의존 방향이 반대다.
  - 같은 `ref.listen`이 `Navigator.popUntil((route) => route.isFirst)`로 루트까지 스택을 모두 걷어낸다. 책장 탭으로 보내려는 의도는 알겠지만, 설정에서 진입했다면 사용자가 쌓아 둔 설정 화면 스택까지 함께 사라진다.

## 개선 제안

- 완료 메시지 소실 → `ref.listen`의 `completed` 분기에서 pop 전에 `AppSnackBar.success()`(또는 `refreshed == false`면 `AppSnackBar.info()`)로 `state.message`를 띄운다. `AppSnackBar`는 루트 `Overlay`에 그리므로 화면이 pop돼도 남는다.
- 이탈 불가 → `AppLoadingOverlay`를 다시 `body`만 감싸도록 되돌리거나, 오버레이를 유지하려면 진행 중에도 누를 수 있는 취소/닫기 동선을 준다. 최소한 `analyzing` 단계는 취소 가능해야 한다.
- 검증 없는 노트 삭제 → `_removeRestoredBookMemos()`를 `ExternalRecordImportService` 쪽(또는 전용 service)으로 옮기고, "복구된 책 + 이번에 올리지 않은 노트/메모만 삭제 대상"을 확인하는 테스트를 추가한다. 삭제 대상 수를 `[외부 기록 가져오기 흐름] deletedNoteCount=… deletedMemoCount=…` 형태로 로그에 남겨 사후 추적이 가능하게 한다.
- 덮어쓰기 고지 불일치 → 다이얼로그 문구에 카테고리·총 페이지 override 초기화를 추가하고 표지는 유지된다고 바로잡는다. 카테고리를 지우지 않는 게 맞다면 덮어쓰기용 `BookItem`에 `displayCategoryId`(및 유지하고 싶은 필드)를 기존 책 값으로 채운다. 서버가 무시하는 `external_import_snapshot_builder.dart:80`의 덮어쓰기 표지 등록은 제거한다.
- 로그 방식 분기 → 세 파일을 `developer.log`로 되돌려 기존 32개 파일과 맞춘다. 스택 트레이스와 서버 원문은 `kDebugMode` 가드 안에서만 남기고, 릴리즈 로그에는 `result`/`reason`/`status`/식별자만 남긴다.
- 시작 로그 위치 → 저장 모드 확인과 상태 전환까지 끝난 뒤(`state.copyWith(phase: importing)` 직후)로 `'[외부 기록 가져오기 시작]'` 로그를 옮긴다.
- 센티널 문자열 비교 → `RecordImportException`에 `hasServerMessage`(또는 `serverMessage` 필드)를 추가해 `_mapError()`가 명시적으로 표시하고, `_userMessage()`는 그 플래그로 분기한다.
- 전체 동기화 2회 → 사후 정리를 Import 완료 직후 한 번에 끝내고 전체 동기화를 1회로 합친다. 복구된 책이 없으면(`restoredBookServerIdByIsbn.isEmpty`) 기존 증분 동기화만 돌리는 분기를 둔다.
- 목록 가상화 → `SingleChildScrollView` + `shrinkWrap` 조합을 `CustomScrollView` + `SliverList`(헤더는 `SliverToBoxAdapter`, 버튼은 `bottomNavigationBar` 또는 `SliverFillRemaining`)로 바꾸고, `_BookSelectionTile`이 선택 상태만 구독하도록 좁혀 토글 시 전체 재빌드를 피한다.
- 안내와 실패 혼용 → `startImport()`가 실패 메시지와 안내 메시지를 구분해 돌려주게 하고(예: 결과 타입 또는 `isFailure` 플래그), 안내는 `AppSnackBar.info()`, 실패만 `AppAlert`로 띄운다.
- 체크박스 접근성 → `IgnorePointer` 대신 `Checkbox`의 `onChanged`에 실제 토글을 연결하고 타일 전체는 `InkWell` + `MergeSemantics`로 묶는다. 타일 최소 높이를 48dp 이상으로 잡는다.
- 레이어 역참조 → `mainShellTabIndexProvider`를 `lib/app/` 아래 별도 provider 파일이나 `lib/core/`로 옮겨 feature가 `main_shell.dart` 자체를 import하지 않게 한다. 화면 복귀는 루트까지 걷어내는 `popUntil` 대신, 진입 지점이 결과를 받아 처리하도록(예: `Navigator.pop(context, true)`) 바꾸는 편이 진입 경로별 스택을 보존한다.
