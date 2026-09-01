# 리뷰 결과

## 요약
- `flutter analyze`는 통과했지만, 기존 DB를 v18로 올릴 때 `wantToReread`의 서버 값을 잃거나 서버 값을 `false`로 덮을 수 있는 데이터 정합성 문제 2건이 있다.

## 문제점
- [문제] [높음] `lib/features/bookshelf/data/bookshelf_database.dart:266`에서 기존 `user_book` 행의 `want_to_reread`를 모두 `0`으로 채우지만 `sync_meta.last_synced_at`은 유지한다. 이후 `BookshelfRepository.sync()`는 동기화 기준값이 남아 있으면 전체 조회가 아니라 증분 조회만 수행하므로, 서버에서 이미 `wantToReread=true`였지만 마지막 동기화 이후 수정되지 않은 책은 응답에 포함되지 않는다. 이 책은 로컬에서 계속 `false`로 보이고, 사용자가 완독/재독 팝업을 확인하면 그 잘못된 값이 서버에도 저장될 수 있다.
- [문제] [높음] `lib/features/bookshelf/models/record_patch.dart:175`와 `lib/features/bookshelf/models/record_patch.dart:205`는 변경 필드를 알 수 없는 레거시 dirty 행에도 새 필드인 `wantToReread`를 전송 대상으로 추가한다. 해당 행은 v18 마이그레이션에서 서버 값을 모른 채 `false`로 채워지고, 동기화가 전체 조회보다 dirty push를 먼저 수행하므로 서버의 기존 `true`를 `false`로 덮어쓸 수 있다.

## 개선 제안
- v18 마이그레이션 시 서버 모드의 기존 행이 새 필드를 전체 응답으로 다시 받도록 `sync_meta`의 책장 `last_synced_at` 기준값을 무효화한다. `wantToReread=true`인 기존 서버 행이 마지막 증분 기준 이후 변경되지 않은 경우를 포함한 마이그레이션 검증을 추가한다.
- 레거시 스냅샷에는 당시 앱이 알지 못했던 `wantToReread`를 포함하지 않는다. `RecordPatch.fromSnapshot()`은 `dirty_fields`에 `wantToReread`가 명시된 경우에만 이 필드를 보내고, `nonNullFieldsOf()`의 레거시 기본 집합에서도 제외한다. v17 DB의 `dirty_fields=NULL`, 로컬 기본값 `false`, 서버 값 `true` 조합에서 dirty push가 `wantToReread`를 보내지 않는지 검증한다.
