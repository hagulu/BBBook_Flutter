# 리뷰 결과

## 요약
- 정적 분석은 통과했고 PATCH의 생략·수정·삭제 구분과 dirty 필드 누적 방향은 적절하지만, 완독일 삭제의 서버 계약 불일치와 push 확정 시 최신 편집 유실 가능성이 남아 있다.

## 문제점
- [문제][높음][완독일 삭제 불일치] `BookRecordScreen._pickDate()`는 완독일의 "선택 해제"를 항상 `PatchField.clear()`로 만들어 로컬 `finishedAt`을 즉시 `null`로 바꾼다. 그러나 API 문서상 수정 결과의 상태가 `FINISHED`이면 `finishedAt: null`은 삭제가 아니라 기존 완독일 유지(없으면 오늘 설정)로 처리된다. 따라서 완독 상태의 책에서 이 동작을 실행하면 화면은 삭제된 것처럼 보이지만 서버는 값을 유지하고, push 응답이 DB에 반영되거나 화면을 다시 열었을 때 날짜가 되살아난다. 현재 테스트도 `BookItem.copyWithRecord()`가 로컬 값을 지우는지만 확인하고 이 서버 예외 규칙은 검증하지 않는다. (`lib/features/book_record/screens/book_record_screen.dart:502`, `lib/features/bookshelf/models/book_item.dart:219`, `lib/features/bookshelf/models/record_patch.dart:169`)
- [문제][높음][최신 편집 유실] push 성공 경로는 `_dao.getById()`로 읽은 `latest.updatedAt`을 비교한 뒤 별도 `confirmPush()` 트랜잭션에서 서버 스냅샷을 `INSERT OR REPLACE`하고 `dirty_fields`를 무조건 비운다. 최신 여부 확인과 확정 쓰기가 원자적이지 않아 그 사이 새 로컬 편집이 저장되면 해당 값과 dirty 필드 목록이 서버 응답으로 덮인다. 409 경로는 더 직접적으로, 요청 중 새 편집이 추가됐는지 확인하지 않고 `resolveConflict()`가 행 전체의 dirty 상태를 해제한다. 책별 push 큐는 네트워크 요청끼리만 직렬화하고 로컬 편집은 기다리지 않으므로, 이번에 추가한 필드 단위 dirty 추적만으로는 이 유실을 막지 못한다. (`lib/features/bookshelf/data/bookshelf_repository.dart:226`, `lib/features/bookshelf/data/bookshelf_repository.dart:240`, `lib/features/bookshelf/data/bookshelf_repository.dart:261`, `lib/features/bookshelf/data/bookshelf_dao.dart:517`, `lib/features/bookshelf/data/bookshelf_dao.dart:537`)

## 개선 제안
- 완독 상태의 완독일 선택 해제 → 서버 정책에 맞춰 해당 상태에서는 선택 해제를 숨기거나, 제품 정책상 삭제가 필요하면 상태 전환을 같은 PATCH에 포함한다. 서버가 값을 보정할 수 있는 요청은 응답의 `BookItem`을 컨트롤러 상태에도 반영하고, `FINISHED + finishedAt clear` 조합을 API 계약 테스트에 추가한다.
- push 응답과 새 로컬 편집의 경합 → 요청 시작 시점의 로컬 revision(또는 캡처한 `updated_at`)을 DAO에 전달하고, `confirmPush`·`resolveConflict`가 같은 DB 트랜잭션 안에서 revision 일치 여부를 확인한 경우에만 값과 dirty 상태를 교체한다. 불일치하면 최신 로컬 값과 `dirty_fields`는 유지하고 성공 응답의 서버 `updatedAt`만 다음 push 기준값으로 갱신한다.
