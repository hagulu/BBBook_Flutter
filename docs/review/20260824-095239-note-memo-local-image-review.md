# 리뷰 결과

## 요약
- 로컬 사진 저장과 서버 동기화의 기본 흐름은 일관되지만, 반복 다운로드 실패가 발생하면 오래된 사진의 로컬 저장이 영구적으로 밀릴 수 있습니다.

## 문제점
- [중간] `BookNoteRepository._runHydration()`은 매번 `updated_at DESC`로 조회한 최대 50개만 처리하고, 다운로드에 실패한 메모는 `local_image_path`가 계속 `null`인 채 남습니다. 따라서 최신 50개 중 하나 이상이 지속적으로 실패하는 상황에서 대상 수가 계속 한도에 도달하면 같은 실패 항목들이 다음 실행에도 앞자리를 차지합니다. 최신 50개가 모두 실패하거나 실패 항목과 새 항목이 계속 누적되면 51번째 이하의 오래된 사진은 한 번도 다운로드를 시도하지 못하며, `targets.length >= 50` 조건 때문에 orphan 정리도 계속 건너뜁니다. (`lib/features/book_note/data/book_note_repository.dart:823`, `lib/features/book_note/data/book_note_repository.dart:831`, `lib/features/book_note/data/book_note_repository.dart:851`)

## 개선 제안
- 고정된 최신 50개 재조회로 인한 기아 → hydration 대상에 커서/순환 순서를 적용하거나, 실패 시 재시도 시각·횟수를 기록해 다음 회차에서는 실패 항목을 뒤로 미루고 아직 시도하지 않은 메모도 처리되게 합니다. orphan 정리 여부도 최초 조회 개수가 아니라 처리 후 DB에 남은 대상의 존재 여부를 다시 조회해 결정하는 편이 안전합니다.
