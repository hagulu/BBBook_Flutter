# 리뷰 결과

## 요약
dirty push와 세션 응답 차단은 구현돼 있지만, 원격 삭제 후 관계 보존과 충돌 처리에서 데이터 무결성 문제가 있습니다. P1 2건, P2 1건입니다.

## 확인 범위
앱 복귀·주기 동기화, 전체/증분 전환, 책별 push 큐, dirty 보호, 원격 삭제, 충돌, 서버 모드 로그아웃의 최종 동기화를 검토했습니다.

## 문제점

### [SYNC-01][P1] 원격 삭제된 책의 음수 로컬 ID가 재사용되면 과거 노트가 새 책에 붙을 수 있음

- 근거: [lib/features/bookshelf/data/bookshelf_dao.dart:316](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_dao.dart:316) 및 [lib/features/bookshelf/data/bookshelf_dao.dart:362](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_dao.dart:362)은 서버에서 사라진 clean 책을 삭제하고 태그 매핑만 명시적으로 정리합니다. `book_note`와 `book_reflection`에는 부모 책 FK가 없어 하위 기록이 남습니다. [lib/features/bookshelf/data/bookshelf_database.dart:268](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_database.dart:268)의 스키마와 [lib/features/bookshelf/data/bookshelf_dao.dart:1386](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_dao.dart:1386)의 `MIN(user_book_id) - 1` 재할당을 함께 보면 충돌이 발생합니다.
- 일반 재현: 이 앱에서 만든 A 책의 로컬 ID가 -1인 상태에서 동기화를 완료하고, A에 아직 전송되지 않은 메모를 남깁니다. 웹/다른 기기에서 A를 삭제해 앱에 반영한 뒤 B를 추가합니다. 더 작은 음수 책이 남아 있지 않으면 B가 -1을 다시 받습니다.
- 영향: 남은 A의 하위 기록이 B의 노트·독후감으로 조회됩니다. 특히 dirty 하위 기록은 원격 삭제 반영에서도 보호되므로, 다음 동기화가 반드시 이 관계를 정리한다고 볼 수 없습니다. 이후 서버 ID 해석도 B를 기준으로 이뤄져 잘못된 관계로 쓰기를 시도할 수 있습니다.

### [SYNC-02][P1] 409 충돌을 만나면 미전송 편집의 dirty 표시와 변경 필드가 조용히 사라짐

- 근거: [lib/features/bookshelf/data/bookshelf_repository.dart:444](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_repository.dart:444)의 일반 기록 PATCH 충돌은 `resolveConflict()`로 이어집니다. [lib/features/bookshelf/data/bookshelf_dao.dart:828](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_dao.dart:828)은 요청 중 추가 편집이 없으면 `is_dirty=0`, `dirty_fields=null`로 바꾸고 동기화 기준을 지웁니다. 후속 전체 조회는 그 행을 서버 값으로 덮어쓸 수 있습니다.
- 조건: 휴대폰에서 오프라인으로 한줄평·별점·독서 상태 등을 수정한 사이 웹/다른 기기에서도 같은 책을 수정하고, 휴대폰이 다시 연결됩니다.
- 영향: 사용자가 저장했다고 본 편집이 확인이나 복구 수단 없이 폐기됩니다. 이 충돌은 로그에만 남아 일반 동기화 오류 안내나 로그아웃의 dirty 확인에서도 유실 후보가 드러나지 않을 수 있습니다.

### [SYNC-03][P2] 전체 다운로드의 증분 기준에 서버 시각 대신 기기 시각을 사용하는 경로가 남음

- 근거: [lib/features/bookshelf/data/bookshelf_repository.dart:225](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_repository.dart:225), [lib/features/book_note/data/book_note_repository.dart:514](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_note/data/book_note_repository.dart:514), [lib/features/book_reflection/data/book_reflection_repository.dart:335](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_reflection/data/book_reflection_repository.dart:335), [lib/features/tag/data/tag_repository.dart:122](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/tag/data/tag_repository.dart:122) 및 최초 동기화가 요청 직전의 기기 `DateTime.now()`를 기준으로 저장합니다. records 응답 모델에는 `exportedAt`이 있습니다.
- 조건/영향: 기기 시계가 서버보다 앞서 있으면 전체 조회 후부터 그 기준 시각까지의 다른 기기 변경이 다음 증분 범위에서 빠질 수 있습니다. 긴 기간의 큰 시계 오차를 전제로 한 지적이 아니라, 전체 스냅샷과 증분 커서의 시계 기준이 다르다는 문제입니다.

## 개선 제안

- SYNC-01: 하위 참조가 남은 로컬 ID를 다시 할당하지 않습니다. 영속적인 ID 할당 또는 부모 tombstone 유지 중 기존 구조에 맞는 방식을 택하고, dirty 자식을 일괄 삭제하는 대응은 피합니다.
- SYNC-02: 거절된 편집을 보존하고 충돌임을 식별할 수 있게 합니다. 기존 dirty/defer 상태를 활용하되, 무조건 로컬 우선 재전송으로 바꿔 다른 기기 값을 덮어쓰는 방식은 사용하지 않습니다. 최소한 선택 또는 복구 가능한 사본이 필요합니다.
- SYNC-03: records 전체 응답의 `exportedAt` 등 서버가 보장하는 시각을 커서로 사용합니다. 책장 전용 전체 API에 같은 값이 없으면 서버 커서를 얻을 수 있는 기존 조회 경로와 맞추고, 임의의 시간 보정 상수는 넣지 않습니다.

## 확인된 보호 장치

책·노트·독후감·태그 push는 항목별 큐로 직렬화합니다. 저장 당시 updatedAt을 비교해 응답 중 새 편집을 덮지 않으며, 세션 변경 응답을 차단합니다. 백그라운드에서는 30초 확인·15초 재시도 제한과 부모 책 우선 순서를 사용합니다. OS가 프로세스를 유지해 주는 백그라운드 업로드를 보장하는 구조는 아니며, 일반 dirty 기록은 복귀 후 재전송하는 방식입니다.
