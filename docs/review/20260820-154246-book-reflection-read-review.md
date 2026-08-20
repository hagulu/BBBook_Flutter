# 리뷰 결과

## 요약
- 독후감 읽기 화면은 정적 분석을 통과했지만, 목록 노출 범위와 증분 동기화 기준값 때문에 초안 노출 및 서버 변경 누락 가능성이 있다.

## 문제점
- [문제][높음][데이터/노출 범위] `book_reflection_dao.dart:20-34`는 해당 책의 로컬 독후감을 상태 구분 없이 전부 반환한다. 데이터 원본인 `GET /api/me/records`와 증분 API는 독후감 테이블 전체를 내려주지만 `ServerBookReflection`(`record_sync_payload.dart:80-118`)에는 `status`가 없어 `DRAFT`와 `PUBLISHED`를 구분할 수도 없다. 반면 화면이 대체하는 `GET /api/me/books/{userBookId}/reflections`는 `PUBLISHED`만 반환한다고 명시한다. 따라서 서버에 저장된 초안이 일반 독후감처럼 목록과 읽기 전용 상세에 노출될 수 있고, 제목·본문이 완성되지 않은 초안도 공개된 기록처럼 보인다.
- [문제][높음][동기화] 초기 기록 저장은 `record_sync_dao.dart:156-161`에서 기기 시각인 `requestedAt`을 `last_synced_at_reflection`으로 저장하고, 별도 전체 동기화도 `book_reflection_repository.dart:89-108`에서 `DateTime.now()`를 같은 기준값으로 사용한다. 같은 파일의 `:66-68`이 설명하듯 기기 시계가 서버보다 앞서 있으면 이후 서버 변경의 `updatedAt`이 `since`보다 작아져 그 차이가 해소될 때까지 독후감 생성·수정·삭제를 받지 못한다. `fullSyncRequired` 경로만 서버의 `syncedAt`을 쓰므로 최초 로그인과 기준값 초기화 후 전체 동기화에는 보호가 적용되지 않는다.
- [문제][낮음][접근성] `book_reflection_list.dart:151-175`와 상세 화면의 공개/비공개 표시는 의미가 있는 globe/lock 아이콘에만 의존하며 `semanticLabel`이나 텍스트가 없다. 스크린 리더 사용자는 독후감의 공개 여부를 확인할 수 없다.

## 개선 제안
- 초안과 발행본을 구분할 수 없는 로컬 모델 → 전체/증분 API 응답에 `status`를 포함해 로컬 스키마와 모델에 저장하고 목록 쿼리를 `PUBLISHED`로 제한한다. API 변경 전에는 전용 목록 API를 사용하거나, 전체 동기화 API가 발행본만 반환한다는 계약을 문서와 응답 규격에 명시해 노출 범위를 확정한다.
- 클라이언트 시각을 증분 `since`로 사용 → 전체 조회 응답에 서버 기준 `syncedAt`을 추가해 그 값을 저장하거나 HTTP `Date` 등 신뢰 가능한 서버 시각을 기준으로 삼는다. 서버 기준값을 얻을 수 없다면 클라이언트 시각을 미래 방향으로 저장하지 않도록 보수적인 기준값과 중복 허용 upsert 전략을 사용한다.
- 공개 상태가 아이콘에만 표현됨 → 아이콘에 `semanticLabel`을 지정하거나 `Semantics`로 카드 설명에 “공개 독후감”/“비공개 독후감”을 포함한다.
