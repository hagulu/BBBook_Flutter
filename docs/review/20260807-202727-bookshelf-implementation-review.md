# 리뷰 결과

## 요약
- 책장 기능의 feature/data/provider 분리와 전체·증분 동기화 트랜잭션 구조는 대체로 적절하지만, 현재 로컬 DB가 사용자와 결합되어 있지 않고 동기화·로그아웃도 직렬화되지 않아 다른 계정의 책이 노출될 수 있는 경로를 우선 차단해야 한다.
- `flutter analyze` 결과 error/warning은 없으며 `prefer_initializing_formals` info 9건(기존 인증 6건, 신규 책장 3건)이 확인됐다. 동작 문제는 아니므로 아래 문제점에서는 제외했다.

## 문제점
- [높음][계정 데이터 격리] `lib/features/auth/providers/auth_notifier.dart:42`는 앱 시작 refresh 결과가 `null`이면 인증 상태만 변경하고 책장 DB를 지우지 않으며, `:76`의 새 로그인도 기존 로컬 책장의 소유자를 확인하지 않는다. 반면 `lib/features/bookshelf/data/bookshelf_database.dart:20`은 모든 사용자가 하나의 `bookshelf.db`와 `last_synced_at`을 공유한다. 따라서 A 사용자의 refresh token이 만료·삭제된 뒤 B 사용자가 로그인하면 `lib/features/bookshelf/providers/bookshelf_providers.dart:52`가 A의 최근 동기화 시각 때문에 동기화를 10분간 건너뛰어 A의 책을 그대로 보여줄 수 있다. 이후 증분 동기화를 해도 B 계정의 삭제 목록에는 A의 ID가 없으므로 두 계정 데이터가 합쳐질 수 있다.
- [높음][비동기 경쟁 조건] `lib/app/main_shell.dart:48`과 각 탭의 pull-to-refresh는 동일한 `syncNow()`를 중복 호출할 수 있지만 `lib/features/bookshelf/providers/bookshelf_providers.dart:36`에는 실행 중 Future를 재사용하거나 후속 호출을 막는 장치가 없다. 더 큰 문제는 로그아웃 시 `lib/features/auth/providers/auth_notifier.dart:140`에서 provider를 무효화해도 이미 시작된 `BookshelfRepository.sync()`의 네트워크 요청과 DB 쓰기는 취소되지 않는다는 점이다. 로그아웃의 `clearAll()` 직후 이전 계정의 응답이 `reconcile`/`applyChanges`를 실행하면 지운 데이터가 다시 저장되어 다음 로그인 사용자에게 노출될 수 있다.
- [중간][초기 로딩·오류 상태] `lib/app/main_shell.dart:31`은 최초 동기화를 fire-and-forget으로 시작하지만 책장 화면은 `bookshelfSyncControllerProvider` 상태를 관찰하지 않고 로컬 목록 provider만 읽는다. 새 설치에서는 동기화 중에도 빈 상태가 먼저 보이고, 최초 동기화가 실패하면 컨트롤러의 `AsyncError`가 화면에 소비되지 않아 실제 책이 있는 사용자에게 계속 “책이 없습니다”라고 표시된다.
- [중간][완독 컨트롤 동작] `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:41`은 상단 검색·필터 영역을 `floating+snap`으로 설명하고 위로 스크롤하면 다시 나타난다고 명시하지만 실제 `SliverAppBar`는 `:165`에서 `floating: false`이고 `snap`도 설정하지 않는다. 목록 중간에서 위 방향으로 스크롤해도 컨트롤이 나타나지 않으며, 검색이나 필터를 다시 사용하려면 목록 맨 위까지 돌아가야 한다.
- [조건부/중간][대량 책장] `lib/features/bookshelf/data/bookshelf_dao.dart:153`은 전체 동기화의 모든 `userBookId`를 하나의 `NOT IN` 바인딩으로 만들고, `:224`도 탭의 모든 책 ID를 하나의 `IN` 쿼리에 전달한다. 전체 동기화 API에는 페이지네이션이 없으므로 책 수가 플랫폼 SQLite의 바인딩 변수 상한을 넘으면 전체 동기화나 완독 목록 조회가 `too many SQL variables`로 실패한다.
- [낮음][접근성] `lib/features/bookshelf/screens/widgets/finished_filter_panel.dart:113`의 필터 칩은 `GestureDetector`와 작은 `Container`만 사용해 버튼/선택 상태 semantics와 키보드 포커스를 제공하지 않고, 높이도 권장 터치 영역보다 작다. `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:419`의 공개 설정 `IconButton`도 `tooltip` 또는 명시적 semantic label이 없어 현재 공개 상태와 동작을 스크린 리더 사용자가 알기 어렵다.

## 개선 제안
- 사용자와 무관한 단일 DB·동기화 기준값 → 인증된 user ID를 DB 파티션 또는 `sync_meta`의 owner로 저장하고, 로그인 사용자가 owner와 다르면 목록과 기준값을 원자적으로 비운 뒤 반드시 전체 동기화한다. refresh 실패나 새 로그인처럼 명시적 로그아웃을 거치지 않는 인증 전이도 같은 소유자 검증 경로를 사용한다.
- 동기화 중복 및 로그아웃 후 늦은 DB 반영 → 컨트롤러에서 실행 중 동기화 Future를 공유해 호출을 단일화하고, 동기화 시작 시 캡처한 user ID/session generation이 응답 시점에도 같은지 확인한 뒤에만 DB에 반영한다. 로그아웃의 clear와 동기화 apply도 같은 직렬화 경계를 사용해 clear 이후 이전 세션 쓰기가 실행되지 않게 한다.
- 최초 동기화 실패가 빈 목록으로 보임 → 로컬 DB에 기준값이 없는 초기 hydration 동안은 동기화 상태를 화면이 관찰해 loading/error/retry를 표시한다. 기존 캐시가 있는 후속 동기화에서는 목록을 유지한 채 갱신 오류만 별도로 안내하면 된다.
- 위로 스크롤해도 검색·필터가 재노출되지 않음 → 문서화된 동작이 요구사항이면 `floating: true`, `snap: true`로 맞추고 월 인덱스 점프 오프셋도 실제 app bar 동작과 함께 검증한다. 현재 동작이 의도라면 오해를 만드는 주석을 수정하고 컨트롤 재진입 UX를 별도로 제공한다.
- 책 수에 비례해 SQL 바인딩 수 증가 → ID를 플랫폼 상한보다 작은 단위로 나누어 조회·삭제하거나, 전체 동기화 ID를 임시 테이블에 넣고 join/`NOT EXISTS`로 reconcile한다. 태그 조회도 ID batch별 결과를 합치도록 제한한다.
- 필터·공개 토글의 보조 기술 정보 부족 → 필터 칩은 `FilterChip`/`ChoiceChip` 또는 `Semantics(button: true, selected: ...)`와 키보드 포커스를 사용하고 최소 터치 영역을 확보한다. 공개 토글에는 현재 상태가 포함된 `tooltip`/semantic label을 제공한다.
