# 리뷰 결과

## 요약
- `flutter analyze`는 통과했지만, 기존 DB의 `wantToReread` 값을 잃거나 서버에 잘못 덮어쓰는 미해결 문제 2건과 compact 토글의 접근성 문제 1건이 있다.

## 문제점
- [문제] [높음·미해결] `lib/features/bookshelf/data/bookshelf_database.dart:266`에서 기존 행의 `want_to_reread`를 모두 `0`으로 채운 뒤 `sync_meta.last_synced_at`을 유지한다. 초기 통합 동기화 완료 키도 앱 업데이트만으로는 무효화되지 않으므로, 기존 사용자는 전체 조회 없이 증분 동기화로 진입한다. 서버에서 이미 `wantToReread=true`지만 마지막 동기화 이후 바뀌지 않은 책은 증분 응답에 포함되지 않아 로컬에 계속 `false`로 남고, 이후 완독/재독 확인 시 잘못된 값이 서버에도 저장될 수 있다.
- [문제] [높음·미해결] `lib/features/bookshelf/models/record_patch.dart:175`와 `lib/features/bookshelf/models/record_patch.dart:205`는 변경 필드를 알 수 없는 레거시 dirty 행에도 새 필드인 `wantToReread`를 포함한다. v18 마이그레이션이 만든 로컬 기본값 `false`를 전체 동기화보다 먼저 수행되는 dirty push가 서버에 보내므로, 서버의 기존 `true`를 `false`로 덮어쓸 수 있다.
- [문제] [보통] `lib/features/book_record/screens/widgets/want_to_reread_toggle.dart:29`의 compact 토글은 시각 요소와 `InkWell`의 높이가 30px이고 추가 세로 패딩이나 최소 제약이 없다. 완독·재독 시트 제목 옆의 주요 토글이 권장 최소 터치 영역인 44~48 논리 픽셀보다 작아 손가락 터치와 운동 보조 접근성이 떨어진다.

## 개선 제안
- v18 마이그레이션에서 책장 `last_synced_at`을 무효화해 기존 서버 행을 전체 조회로 다시 받는다. 기존 초기 통합 동기화 완료 키가 남아 있는 실제 업그레이드 경로에서 `wantToReread=true`가 복원되는지 검증한다.
- 레거시 스냅샷은 `dirty_fields`에 `wantToReread`가 명시된 경우에만 해당 필드를 전송하도록 하고, `nonNullFieldsOf()`의 레거시 기본 집합에서는 새 필드를 제외한다. `dirty_fields=NULL`, 로컬 기본값 `false`, 서버 값 `true` 조합의 재전송 검증을 추가한다.
- compact 배지의 시각 크기는 유지하되 `InkWell` 바깥에 최소 44~48px 높이의 `ConstrainedBox`나 투명 패딩을 적용해 전체 터치 영역을 넓힌다.
