# 리뷰 결과

## 요약
기록 편집의 로컬 우선 저장과 서버 push 큐는 갖춰져 있으나, 로컬 모드 ISBN 연결의 중복 검사에 P2 1건이 있습니다.

## 확인 범위
독서 상태·진행률·별점·한줄평·출처·전체 쪽수·재독·완독일, 책 정보/표지 수정, 태그 추가·삭제, 책 삭제, ISBN 개별/일괄 연결과 건너뛰기·중단을 확인했습니다.

## 문제점

### [REC-01][P2] 로컬 모드에서 두 책에 같은 ISBN을 연결할 수 있어 동기화 켜기가 실패함

- 근거: [lib/features/book_record/data/book_record_repository.dart:362](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_record/data/book_record_repository.dart:362)의 `_linkBookLocally()`는 다른 활성 책의 ISBN을 확인하지 않고 변경합니다. user_book에는 활성 ISBN 고유 제약도 없습니다. 일괄 연결도 이 메서드를 사용합니다.
- 일반 재현: 가져온 커스텀 책 A를 이미 서재에 있는 ISBN 책 B와 같은 검색 결과에 연결하거나, 일괄 연결에서 같은 결과를 두 번 고릅니다.
- 영향: 로컬 목록에는 두 책이 남지만 서버 Import는 서로 다른 localId가 같은 ISBN 서버 행으로 해석되는 것을 금지해 전체를 롤백합니다. 현재 스냅샷 사전 검증도 ISBN 중복을 확인하지 않아 전송 후에야 실패를 알 수 있습니다.
- 계약 근거: [../../api-doc/api-me-records-import-importId-items-post.md:144](/Users/hagulu/develop/service/BBBook/project/app/bbbook/../../api-doc/api-me-records-import-importId-items-post.md:144)의 세션 전체 1:1 매핑 규칙.

## 개선 제안

로컬 연결 저장 트랜잭션에서 자기 자신을 제외한 활성 ISBN 중복을 확인하고 기존 책이 있다는 안내로 중단합니다. Import 사전 검증에도 같은 조건을 추가해 이미 있는 중복을 전송 전에 알립니다. 노트·메모를 자동 병합하거나 기존 책을 지우는 대응은 부작용이 커 권하지 않습니다.

## 확인된 보호 장치

- 일반 기록 편집은 로컬에 저장한 뒤 재전송하며, 부분 PATCH의 생략/수정/null 삭제를 구분합니다.
- 책 정보에서 전체 쪽수를 줄이면 진행 페이지를 보정하고, 출처 변경도 매체별 진행 값으로 정규화합니다.
- 서버 모드 ISBN 연결은 미전송 기록을 먼저 push하고 같은 책의 직렬 큐에서 처리합니다.
- 태그는 로컬 ID와 서버 ID를 구분하고, 같은 이름 태그 병합과 dirty 매핑 보호가 있습니다.
- 책의 명시적 삭제는 로컬 하위 데이터·이미지를 함께 정리합니다. **원격 삭제 경로의 차이**는 [SYNC-01](../02-sync/20261028-124818-background-data-integrity.md)에 있습니다.
- 409 후 일반 편집 유실은 같은 문서의 SYNC-02입니다.

## 후속 확인 시나리오

두 필드 연속 수정, 총 쪽수 변경과 진행률 변경, 업로드 중 표지 재선택, 오프라인 태그 추가 후 삭제, 삭제한 ISBN 재등록, 일괄 연결의 즉시 저장 실패·건너뛰기·중단을 확인합니다. 중단할 때 이미 저장한 앞선 책을 되돌리는 동작은 요구하지 않습니다.
