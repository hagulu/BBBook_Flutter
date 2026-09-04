# 리뷰 결과

## 요약
- `flutter analyze`는 통과했고 검토 도중 추가된 책 검색 기본 30건 변경에서는 별도 문제를 찾지 못했지만, 태그 변경에는 원격 책 삭제 뒤 남은 매핑이 새 책에 붙을 수 있는 정합성 문제와 동기화 결과가 책장 UI에 반영되지 않는 문제, 전체 동기화 중 누락된 매핑을 다시 받을 수 없게 만드는 기준 시각 문제가 있습니다.

## 문제점
- [문제] [높음] `lib/features/bookshelf/data/bookshelf_dao.dart:206`과 `lib/features/bookshelf/data/bookshelf_dao.dart:241`은 전체·증분 책장 동기화에서 `user_book`만 삭제하고, 외래 키를 의도적으로 제거한 `user_book_tag_map`은 정리하지 않습니다. 직접 삭제 경로인 `lib/features/bookshelf/data/bookshelf_dao.dart:317`에는 매핑 정리가 있지만 원격 삭제 반영 경로에는 같은 처리가 없습니다. 특히 서버 ID가 확정된 로컬 생성 책은 음수 로컬 ID를 유지할 수 있는데, 해당 책에 아직 서버 ID가 없는 dirty 태그 매핑이 남은 상태에서 다른 기기가 책을 삭제하면 태그 증분 동기화의 `deletedTagMapIds`로도 이 로컬 매핑을 찾을 수 없습니다. 이후 `_nextLocalUserBookId`가 삭제된 음수 ID를 새 책에 재사용하면 이전 책의 태그가 새 책에 붙고, dirty push가 그 태그를 새 책 서버 데이터에 전송할 수도 있습니다.
- [문제] [보통] `lib/features/tag/providers/tag_providers.dart:63`은 서버 태그 변경을 반영한 뒤 `tagSyncVersionProvider`와 상세 화면용 `externalSyncVersionProvider`만 갱신하지만, `tagSyncVersionProvider`를 구독하는 화면 provider가 없습니다. 책장 목록과 완독 필터는 `lib/features/bookshelf/providers/bookshelf_providers.dart:136`, `lib/features/bookshelf/providers/bookshelf_providers.dart:198`, `lib/features/bookshelf/providers/bookshelf_providers.dart:227`에서 `bookshelfSyncVersionProvider`만 구독합니다. 따라서 다른 기기에서 태그를 추가·삭제한 뒤 당겨서 새로고침해도 DB만 바뀌고 현재 책장 카드의 태그·완독 태그 선택지·필터 결과는 캐시된 상태로 남습니다.
- [문제] [보통] `lib/features/tag/data/tag_dao.dart:361`은 전체 태그 동기화에서 상위 책을 아직 찾지 못한 매핑을 건너뛰면서도 `lib/features/tag/data/tag_dao.dart:378`에서 `last_synced_at_tag`를 정상 완료 시각으로 저장합니다. 당겨서 새로고침은 `lib/features/bookshelf/screens/widgets/bookshelf_refresh_indicator.dart:22`에서 책장과 태그 동기화를 병렬 실행하므로, 다른 기기에서 새 책과 태그를 함께 만든 직후에는 태그 전체 조회가 책장 반영보다 먼저 끝나 이 경로가 실제로 발생할 수 있습니다. 누락된 매핑의 `updatedAt`이 저장한 기준 시각보다 이전이면 이후 증분 조회에는 다시 포함되지 않아, 별도의 전체 동기화가 강제될 때까지 해당 태그가 영구적으로 보이지 않습니다.

## 개선 제안
- 원격 책 삭제 뒤 태그 매핑 잔존 → `reconcileInTransaction`과 `applyChanges`에서 실제로 삭제된 `user_book_id`의 `user_book_tag_map`을 같은 트랜잭션 안에서 정리하거나, 책 삭제 후 부모가 없는 매핑을 일괄 제거합니다. 서버 ID가 없는 dirty 매핑도 반드시 포함하고, 음수 로컬 ID 재사용 시 이전 태그가 붙지 않는 회귀 테스트를 추가합니다.
- 태그 동기화 후 책장 UI 캐시 유지 → 태그 DB가 바뀌면 `bookshelfSyncVersionProvider`도 갱신해 태그를 포함해 조회하는 책장·완독 필터 provider들을 다시 읽게 하거나, 해당 provider들이 실제 `tagSyncVersionProvider`를 구독하도록 의존성을 정리합니다.
- 전체 동기화 orphan 누락 → 전체 동기화에서도 증분 동기화와 같이 orphan 발생 여부를 추적하고, 하나라도 건너뛰었으면 `last_synced_at_tag`를 저장하지 않아 다음 호출이 다시 전체 동기화를 수행하게 합니다. 또는 당겨서 새로고침에서 책장 동기화를 완료한 다음 태그 동기화를 순차 실행해 상위 책 선반영을 보장합니다.
