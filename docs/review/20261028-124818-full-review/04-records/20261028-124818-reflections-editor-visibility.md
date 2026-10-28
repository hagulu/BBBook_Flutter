# 리뷰 결과

## 요약
독후감 본문 저장은 직렬화돼 있지만 공개 설정이 그 큐를 우회해 비공개 전환과 경합할 수 있습니다. P1 1건입니다.

## 확인 범위
목록·상세·작성/수정, Quill/레거시 본문 변환, 저장하지 않고 나가기, AI 초안 저장, 이미지 매핑·정리, 공개 여부와 삭제를 검토했습니다.

## 문제점

### [REF-01][P1] 본문 push와 비공개 전환이 겹치면 서버 글이 다시 공개될 수 있음

- 근거: [lib/features/book_reflection/data/book_reflection_repository.dart:174](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_reflection/data/book_reflection_repository.dart:174)의 `setPublic()`은 직접 visibility PATCH를 호출하고 로컬 값을 바꿉니다. 본문 push가 사용하는 reflection별 `_dirtyPushChains`에 합류하지 않습니다. [lib/features/book_reflection/data/book_reflection_repository.dart:482](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_reflection/data/book_reflection_repository.dart:482)의 일반 저장 PATCH는 캡처한 `isPublic`도 전송합니다.
- 일반 재현: 공개 독후감을 수정·저장한 직후 상세에서 비공개로 바꿉니다. 느린 통신으로 기존 본문 push가 남아 있고, 비공개 PATCH 뒤에 그 본문 PATCH가 서버에서 처리되면 이전 `isPublic=true`가 다시 반영됩니다.
- 영향: 로컬은 비공개를 표시해도 서버는 다음 dirty 재전송 전까지 공개일 수 있습니다. 같은 문제가 새 글 CREATE 중 공개 설정 변경에서도 생길 수 있습니다. 이후 자동 동기화가 정정할 가능성이 있어도 비공개 전환 직후의 노출을 막아 주지는 못합니다.
- 보조 근거: [lib/features/book_reflection/data/book_reflection_dao.dart:141](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_reflection/data/book_reflection_dao.dart:141)의 공개 변경은 updatedAt만 바꾸며, [lib/features/book_reflection/data/book_reflection_dao.dart:248](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_reflection/data/book_reflection_dao.dart:248)의 본문 응답 보호는 로컬 덮어쓰기만 방지합니다. 이미 서버로 보낸 공개 필드의 처리 순서를 제어하지는 않습니다.

## 개선 제안

공개 설정 쓰기도 같은 독후감의 직렬 큐에서 처리하고, 본문 저장과 최신 공개 값의 순서를 보장합니다. 기존 본문 저장 API에 공개 필드가 필요하므로 단순히 화면 스위치를 잠시 비활성화하는 것만으로 서버의 진행 중 쓰기까지 해결됐다고 판단하면 안 됩니다.

## 관련 핵심 문제

최초 다운로드한 글의 server_id 누락으로 비공개 PATCH 자체가 생략되는 문제는 [INIT-01](../02-sync/20261028-124818-initial-download.md)입니다. 두 원인은 별개입니다.

## 확인된 보호 장치

편집기는 미저장 변경의 종료 확인과 저장 중 종료 차단을 사용합니다. 글 수정·삭제의 dirty push는 같은 글별 큐를 사용하고, 저장 중 새 편집은 응답으로 덮지 않습니다. 새 이미지 첨부 한도와 기존 이미지 표시·매핑을 분리합니다. 현재 독후감 새 이미지 한도는 0이므로 미래에만 가능한 신규 이미지 경로를 가정해 결함을 늘리지 않았습니다.
