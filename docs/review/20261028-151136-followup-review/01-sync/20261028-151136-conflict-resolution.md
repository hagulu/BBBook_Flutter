# 리뷰 결과

## 요약

409에서 서버 수정 시각을 확인하고 로컬 편집이 더 최신이면 다시 보내는 경로가 추가됐습니다. 다만 **확인 요청의 일시적인 HTTP 오류를 서버 우선 판정으로 처리해 편집을 잃는 분기**가 남아 있습니다. P1 1건입니다.

## 문제점

### [FUP-01][P1] 충돌 확인 요청의 5xx·429 실패에도 미전송 편집을 폐기함

**위치**

- [lib/features/bookshelf/data/bookshelf_repository.dart:505](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_repository.dart:505): `_retryNewerLocalEdit()`에서 `ApiException.statusCode != null`이면 곧바로 `false`를 반환합니다.
- [lib/features/bookshelf/data/bookshelf_repository.dart:457](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_repository.dart:457): `false`를 받으면 `resolveConflict()`를 호출합니다.
- [lib/features/bookshelf/data/bookshelf_dao.dart:849](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/bookshelf/data/bookshelf_dao.dart:849): 전송 중 별도 추가 편집이 없으면 `is_dirty=0`, `dirty_fields=null`로 바꾸고 전체 재조회를 유도합니다.
- [lib/features/book_record/data/book_record_api.dart:87](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_record/data/book_record_api.dart:87): 최신 시각 확인용 GET도 실제 HTTP 상태를 가진 `ApiException`으로 실패할 수 있습니다.

**일반적인 발생 조건**

1. 다른 기기에서 책 기록이 바뀐 뒤, 이 기기에서 오프라인으로 짧은 감상·별점 등을 더 늦게 편집합니다.
2. 재연결 후 기존 기준값을 사용한 PATCH가 409를 받습니다.
3. 서버 최신 시각을 읽는 GET이 일시적인 503 또는 429를 받습니다.
4. 최신 시각을 한 번도 얻지 못했는데 `false`가 반환되고, 미전송 편집의 dirty 표시가 지워집니다. 이후 전체 조회가 서버 값으로 로컬을 덮습니다.

서버에서 HTTP 응답을 받았다는 사실은 서버 편집이 더 최신이라는 증거가 아닙니다. 새 코드는 응답 없는 연결 실패에는 dirty를 보존하지만, 응답이 있는 일시 오류에는 반대로 편집을 버립니다. 409 직후 확인 요청 한 번이 실패하는 조건이며 동시 다중 터치나 극단적인 타이밍을 전제로 하지 않습니다.

**영향**

사용자가 마지막으로 편집한 값이 서버에 도달하지 않은 채 재전송 대상에서도 제외됩니다. 일시적인 서버 장애가 개인 기록 유실로 이어집니다. 이번에 도입한 최신 편집 비교 정책 자체의 선호 문제가 아니라, 비교에 실패한 경우를 비교 완료로 취급하는 문제입니다.

## 개선 제안

- 최신 서버 시각을 성공적으로 확인하기 전까지는 `resolveConflict()`로 넘어가지 않습니다. 5xx·429·확인 불가 오류는 dirty를 유지하고 기존 재시도 시점에 다시 판단합니다.
- 삭제·권한 거부 같은 응답이 따로 필요하면 명시적인 정책으로 처리하고, 모든 HTTP 실패를 한 분기로 합치지 않습니다.
- 확인 요청의 성공·실패 어느 경로든 await 이후 세션 세대를 확인한 뒤 DAO를 수정합니다.
- 새 자동 병합 엔진이나 무제한 즉시 재전송은 필요하지 않습니다. 기존 `true`(dirty 유지)와 `false`(서버 우선 확정)의 반환 의미를 오류 분기에도 일관되게 적용하는 범위면 됩니다.

## 후속 검증 시나리오

아직 실행하지 않았습니다. 409 뒤 최신 시각 GET을 각각 503·429·연결 실패로 종료했을 때 dirty·변경 필드·사용자 입력이 유지되는지 확인합니다. 성공한 GET이 로컬보다 최신인 경우와 오래된 경우도 구분해 기존 재전송 정책이 유지되는지 확인합니다.

## 관련 항목

이전 [SYNC-02](../../20261028-124818-full-review/02-sync/20261028-124818-background-data-integrity.md)의 일반 409 경로는 개선됐지만, 이 오류 분기 때문에 전체 해결로 판정하지 않았습니다.
