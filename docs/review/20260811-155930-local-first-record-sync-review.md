# 리뷰 결과

## 요약
- 로컬 우선 편집과 dirty 재시도 기반은 마련됐지만, 요청 경합과 재시도 정보 손실로 사용자의 최신 수정이 사라질 수 있어 현재 상태로 완료하기 어렵다.

## 문제점
- [문제][높음][연속 편집 유실] `lib/features/book_record/providers/book_record_providers.dart:78`의 `_editChain`은 `BookRecordRepository.updateRecord()`가 로컬 저장 직후 반환할 때까지만 직렬화하고, 실제 서버 요청은 `lib/features/book_record/data/book_record_repository.dart:89`에서 `unawaited`로 동시에 실행한다. 따라서 사용자가 진행 쪽수와 별점 등을 연달아 바꾸면 여러 요청이 같은 `synced_updated_at`을 기준으로 경합한다. 먼저 끝난 응답은 `lib/features/bookshelf/data/bookshelf_dao.dart:260`에서 그 뒤의 로컬 편집까지 무조건 덮어쓰고 dirty를 해제하며, 다른 요청의 409 처리는 `:283`에서 행 단위 dirty를 다시 지운다. 응답 순서에 따라 마지막 편집이 로컬·서버 양쪽에서 사라질 수 있다.
- [문제][높음][오프라인 최초 완독 유실] 최초 완독 처리 호출은 `status=FINISHED`를 보내지만 `finishedAt`은 보내지 않아 서버가 오늘 날짜를 정하도록 한다. 즉시 push가 네트워크 오류로 실패하면 로컬에는 `FINISHED`와 `finishedAt=null`만 남는다. 이후 dirty 재시도는 `lib/features/bookshelf/data/bookshelf_repository.dart:117`에서 이 조합의 `status`를 의도적으로 생략하므로, 서버에는 완독 전환이 끝내 반영되지 않는다. 재시도 성공 응답을 `:139`에서 확정하면 로컬 상태도 서버의 이전 상태로 되돌아간다.
- [문제][중간][업그레이드 직후 충돌 검사 우회] v3 마이그레이션은 `lib/features/bookshelf/data/bookshelf_database.dart:40`에서 `synced_updated_at` 컬럼만 추가하고 기존 행의 기준값을 채우거나 전체 동기화를 강제하지 않는다. 업그레이드 후 동기화 전에 편집하면 `getSyncedUpdatedAt()`이 null을 반환하고 PATCH에서 `updatedAt`이 생략되어, 이번 변경에서 도입한 409 충돌 검사가 적용되지 않는다. 그 사이 다른 기기에서 수정된 서버 기록을 첫 로컬 편집이 조건 없이 덮어쓸 수 있다.

## 개선 제안
- 연속 편집의 서버 push가 병렬 실행되고 행 단위 확정이 최신 편집까지 덮어씀 → 책별 단일 push 큐로 서버 응답까지 순차 처리하거나, 로컬 revision/operation ID를 저장해 `confirmPush`·`resolveConflict`가 자신이 시작할 때의 revision과 일치할 때만 dirty를 해제한다. 여러 로컬 편집을 합치는 방식이라면 push 중 추가 편집을 감지해 최신 스냅샷을 새 서버 `updatedAt`으로 다시 전송한다.
- dirty 스냅샷만으로는 `FINISHED + finishedAt=null`이 기존 상태인지 미전송 완독 전환인지 구분할 수 없음 → 변경 필드 또는 pending operation을 함께 저장해 재시도 시 원래의 `status=FINISHED` 의도를 보존한다. 대안으로 로컬 최초 완독 시 서버와 동일한 타임존 기준 `finishedAt`을 함께 기록·전송하되 서버 규격과 날짜 경계를 일치시킨다.
- v3 기존 행은 새 충돌 기준값이 null임 → 신뢰할 수 있는 서버 기준값을 확보할 때까지 첫 편집 전에 전체 동기화를 강제한다. 기존 `updated_at`을 이관하려면 과거 클라이언트 시각으로 저장된 행과 서버 응답으로 저장된 행을 구분할 수 있는지 먼저 확인하고, 구분할 수 없다면 무조건 서버 재조회로 채운다.
