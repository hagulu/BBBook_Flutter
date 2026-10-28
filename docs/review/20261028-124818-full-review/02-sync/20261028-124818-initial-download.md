# 리뷰 결과

## 요약
최초 기록 저장은 트랜잭션으로 묶여 있지만 독후감의 서버 식별자 저장이 빠져 있습니다. P1 1건입니다.

## 확인 범위
최초 다운로드 게이트, 사용자별 완료 표시, 진행률, 세션 변경 중 응답 폐기, 책·노트·메모·독후감·태그 저장을 확인했습니다.

## 문제점

### [INIT-01][P1] 최초 다운로드한 독후감이 서버에 없는 신규 글로 취급됨

- 근거: [lib/features/record_sync/data/record_sync_dao.dart:151](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/record_sync/data/record_sync_dao.dart:151)의 독후감 INSERT에는 `id`만 있고 `server_id`가 없습니다. 모델 변환은 [lib/features/book_reflection/data/book_reflection_dao.dart:626](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_reflection/data/book_reflection_dao.dart:626)에서 `server_id`를 그대로 읽습니다. 같은 최초 저장 경로의 노트·메모에는 서버 ID를 채우고 있습니다.
- 영향: 처음 로그인하거나 로그아웃 후 다시 다운로드한 기존 독후감에 대해 다음 동작이 가능합니다.
  - 수정: Repository가 `serverId == null`을 보고 PATCH 대신 CREATE를 호출해 중복 글을 만듭니다.
  - 삭제: 서버 DELETE를 생략하고 로컬에서만 삭제합니다. 원래 서버 글은 남습니다.
  - 공개/비공개 변경: 서버 PATCH를 생략하고 로컬 표시만 바꿉니다. 공개 글을 비공개로 바꿨다고 생각해도 실제 서버는 공개 상태일 수 있습니다.
- 후속 경로: [lib/features/book_reflection/data/book_reflection_repository.dart:174](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_reflection/data/book_reflection_repository.dart:174), [lib/features/book_reflection/data/book_reflection_repository.dart:401](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_reflection/data/book_reflection_repository.dart:401).
- 자동 복구가 보장되지 않는 이유: [lib/features/record_sync/data/record_sync_dao.dart:194](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/record_sync/data/record_sync_dao.dart:194)이 독후감 증분 기준 시각까지 채웁니다. 기존 글에 새 서버 변경이 없다면 다음 증분 조회는 그 글을 다시 내려주지 않습니다.

## 개선 제안

최초 INSERT에 서버 ID를 함께 채우고, 이미 이 경로로 저장된 정상 양수 ID 행도 안전하게 보정합니다. 이 코드에서 서버 다운로드 행은 `id`가 원래 서버 ID이지만, 모든 로컬 행에 일괄 적용하면 음수 신규 행까지 손상되므로 다운로드 행이라는 조건을 유지해야 합니다.

## 후속 확인 시나리오

서버에 공개 독후감이 있는 계정으로 로컬 DB가 없는 상태에서 로그인한 뒤 수정·삭제·비공개 전환을 각각 확인합니다. 서버에 새 글이 생기지 않고 기존 ID에 정확히 반영돼야 합니다. 기존 잘못 저장된 설치의 보정도 별도로 확인해야 합니다.

## 확인된 보호 장치

전체 저장과 완료 표시는 한 트랜잭션으로 처리합니다. 저장 시작·커밋 전에 세션 세대를 검사하고, 최초 준비가 끝나기 전에는 일반 셸을 표시하지 않습니다. 다만 Android 공유 파일의 별도 진입은 [가져오기 리뷰](../03-imports/20261028-124818-external-import.md)의 확인 항목도 참고해야 합니다.
