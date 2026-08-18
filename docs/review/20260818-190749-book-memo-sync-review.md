# 리뷰 결과

## 요약
- `flutter analyze`는 통과하지만, 현재 변경은 이번 작업에서 명시적으로 제외된 서버 push·증분 동기화를 연결했고 v8 마이그레이션과 세션 전환·동시 편집 경로에 데이터 손상 가능성이 있어 그대로 반영하기 어렵다.

## 문제점
- [높음][요구사항] 이번 작업은 dirty 업로드와 `GET /api/me/memos/sync/changes` 연결을 명시적으로 제외했는데, `lib/features/book_memo/data/book_memo_repository.dart:90,121,159,193`은 모든 로컬 CRUD 직후 `pushMemo()`를 실행하고 `lib/features/book_memo/screens/widgets/book_memo_refresh_indicator.dart:18`은 증분/전체 동기화를 호출한다. 화면 진입 자체는 로컬 조회지만, 구현 범위와 서버 호출 금지 조건을 넘어선 변경이다.
- [높음][마이그레이션] `lib/features/bookshelf/data/bookshelf_database.dart:76-113`은 `oldVersion < 7`에서 현재 버전의 `_createRecordTables()`를 호출해 이미 `server_id`가 있는 테이블을 만든 직후, `oldVersion < 8`에서 같은 컬럼을 다시 `ALTER TABLE ... ADD COLUMN`한다. v6 이하에서 v8로 건너뛰어 업그레이드하면 `duplicate column name`으로 DB 오픈이 실패한다.
- [높음][마이그레이션·데이터] 같은 v8 마이그레이션의 `UPDATE book_memo[_item] SET server_id = id`는 모든 기존 행을 서버 행으로 간주한다(`lib/features/bookshelf/data/bookshelf_database.dart:100-113`). 그러나 직전 v7 코드에도 `_nextLocalId()` 기반 로컬 CRUD가 이미 있어 음수 ID의 미동기화 메모·조각이 존재할 수 있다. 이 행에 음수 `server_id`가 채워지면 이후 생성 대신 음수 ID로 PATCH/DELETE를 반복하며 dirty가 영구히 해제되지 않는다.
- [높음][세션·계정 격리] 제목 push에는 네트워크 응답 뒤 `sessionGeneration` 검사가 있지만, 조각 생성·수정·삭제 경로는 루프 진입 전에만 검사하고 API 응답 뒤 DAO 변경 전에 다시 검사하지 않는다(`lib/features/book_memo/data/book_memo_repository.dart:404-432,447-637`). 로그아웃으로 DB를 비운 뒤 다른 계정이 같은 음수 로컬 ID를 생성하면, 이전 계정의 늦은 응답이 새 행에 `server_id`를 쓰거나 그 행을 물리 삭제할 수 있다. `lib/features/auth/providers/auth_notifier.dart:162-168`도 메모 sync/repository provider를 무효화하지 않는다.
- [높음][동시 편집] 제목 없는 신규 메모를 첫 조각 POST로 만든 뒤 `_confirmMemoBootstrapped()`가 네트워크 요청 전 값이 아니라 응답 후 현재 메모의 `updatedAt`을 다시 읽어 `confirmMemoCreated()`에 넘긴다(`lib/features/book_memo/data/book_memo_repository.dart:503-504,529-541,609-619`). POST 진행 중 사용자가 제목을 입력해도 그 최신 시각을 곧바로 “전송 당시 시각”으로 간주해 `is_dirty=0`으로 만들 수 있으며, 다음 직렬 push는 제목을 서버에 보내지 않는다.
- [높음][사진 데이터] `confirmItemSynced()`는 네트워크 중 추가 편집이 있으면 `server_id`만 기록하고 최신 로컬 필드는 보존하지만, 호출부는 실제 확정 여부와 관계없이 이전 로컬 사진을 삭제한다(`lib/features/book_memo/data/book_memo_repository.dart:622-644`, `lib/features/book_memo/data/book_memo_dao.dart:395-447`). 사진 업로드 중 설명·중요 여부만 수정해 현재 행이 같은 로컬 사진 경로를 계속 참조하는 경우에도 파일이 삭제되어, 다음 dirty 재시도는 존재하지 않는 파일을 업로드하다 계속 실패한다.
- [중간][서버 정합성] 제목 없는 새 메모의 첫 PHOTO를 동기화하기 위해 서버에 임시 SUMMARY 조각을 만든 뒤 PHOTO로 PATCH한다(`lib/features/book_memo/data/book_memo_repository.dart:483-525`). API 문서는 첫 PHOTO 전에 제목 PUT으로 memoId를 확보하도록 규정한다. 이미지 형식·용량·네트워크 오류 또는 로그아웃이 PATCH 전에 발생하면 서버에 빈 SUMMARY 조각이 영구히 남아 다른 클라이언트에도 잘못 노출될 수 있다.
- [낮음][UX] `RefreshIndicator`의 자식 `CustomScrollView`에 `AlwaysScrollableScrollPhysics`가 없다(`lib/features/book_memo/screens/book_memo_list.dart:33-35`). 빈 상태나 카드 수가 적어 콘텐츠가 뷰포트보다 짧으면 당겨서 새로고침 제스처가 시작되지 않아, 동기화 진입점이 필요한 순간에 동작하지 않을 수 있다.

## 개선 제안
- 범위 초과 서버 연결 → 이번 작업에서는 `BookMemoApi`, 자동 `pushMemo`, pull-to-refresh sync 연결을 제외하고 로컬 dirty 유지까지만 남긴다. 증분 동기화는 별도 작업에서 API 문서 기준으로 통합한다.
- 건너뛰기 마이그레이션 실패 → `oldVersion < 7`에서 새 스키마를 만든 경우 v8 `ALTER`를 건너뛰거나, `PRAGMA table_info`로 컬럼 존재 여부를 확인하는 멱등 마이그레이션으로 바꾼다.
- 음수 로컬 ID 백필 → v7의 `id < 0` 또는 로컬 생성 조건에 해당하는 행은 `server_id=NULL`로 유지하고, 서버에서 내려온 행만 `server_id=id`로 백필한다. 마이그레이션 전후 dirty 행 사례를 검증한다.
- 세션 전환 경합 → 조각 API의 모든 `await` 뒤 DAO 쓰기 직전에 generation을 재검사하고 DAO 조건에도 현재 계정/부모 메모를 포함한다. 로그아웃 시 메모 sync/version/repository provider도 무효화해 이전 체인을 폐기한다.
- 제목 dirty 유실 → 조각 POST 전 메모의 `updatedAt`을 캡처해 응답 후 동일할 때만 dirty를 해제하고, `server_id` 확정과 dirty 해제를 분리한다.
- 사진 파일 조기 삭제 → `confirmItemSynced()`가 전체 확정을 적용했는지 반환하게 하거나 DB가 더 이상 해당 경로를 참조하지 않는지 확인한 뒤에만 파일을 삭제한다.
- 첫 PHOTO 임시 조각 → 가짜 SUMMARY를 서버에 만들지 말고 제목이 생길 때까지 PHOTO를 로컬 dirty로 유지하거나, 제목 없는 메모 ID 예약을 지원하는 서버 계약을 별도로 마련한다.
- 짧은 목록 새로고침 → 메모 목록 `CustomScrollView`에 `AlwaysScrollableScrollPhysics`를 적용한다.
