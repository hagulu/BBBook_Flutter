# 리뷰 결과

## 요약
- 기존에 저장된 이미지는 유지·교체할 수 있고 새 이미지에만 제한을 적용하는 기준은 현재 기본 정책에서 지켜집니다. 다만 노트 신규 첨부의 최종 저장 검증과 향후 양수 독후감 한도 처리에는 보완이 필요합니다.

## 문제점
- [P2] 노트 이미지 한도는 편집 화면을 열 때 읽은 개수 스냅샷에만 적용되어 최종 로컬 쓰기를 보호하지 못합니다. 상세 화면은 현재 provider 값에서 개수를 한 번 계산해 편집기에 전달하고(`lib/features/book_note/screens/book_note_detail_screen.dart:326-357`), 편집기는 그 고정값으로 타입 선택과 사진 선택만 막습니다(`lib/features/book_note/screens/widgets/book_note_memo_sheet.dart:315-319,388-413,547-554`). 편집기를 연 동안 백그라운드 동기화가 다른 기기의 사진 메모를 반영하거나 정책 값이 바뀌어도, DAO의 생성·수정 트랜잭션에는 한도 재검사가 없어 그대로 네 번째 사진을 저장합니다(`lib/features/book_note/data/book_note_dao.dart:174-218,226-273`). 이후 서버 400은 push에서 로그로만 소비되어(`lib/features/book_note/data/book_note_repository.dart:668-683`), 제한을 넘은 로컬 메모가 dirty인 채 매 동기화마다 같은 요청을 반복합니다.
- [P2] `reflectionImageLimit`을 숫자로 모델링했지만 실제 화면은 `> 0` 여부만 사용하므로, 한도를 1개 이상으로 바꾸는 순간 신규 이미지 제한을 초과할 수 있습니다. 정책은 향후 서버 등급별 값으로 provider만 교체하면 된다고 설명하지만(`lib/core/policy/attachment_limit_policy.dart:3-8,18-26`), 툴바는 boolean이 true이면 이미지 버튼을 계속 노출하고(`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:727-736,861-871`), 직접 이미지와 사진 메모 삽입 모두 최초 저장 문서와 비교해 새로 추가된 이미지 개수를 세지 않습니다(`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:442-499`). 따라서 예를 들어 신규 첨부 한도가 1이면 기존 저장 이미지는 그대로 통과해야 하지만, 사용자가 이번 편집에서 추가하는 두 번째 새 이미지도 클라이언트가 허용합니다. 서버가 새 이미지만 검증해 거절하더라도 비동기 push 경로에서는 오류가 로그에만 남습니다(`lib/features/book_reflection/data/book_reflection_repository.dart:436-471`).

## 개선 제안
- 노트 편집 시작 시점의 스냅샷 검사 → 화면의 조기 안내는 유지하되, 사진 메모 생성·비사진 메모의 PHOTO 전환을 커밋하는 DAO/Repository 트랜잭션에서 활성 이미지 메모 수를 다시 세어 한도를 원자적으로 검사합니다. 한도 오류는 전용 타입으로 화면까지 반환하고, 동기화 중 원격 사진이 추가되는 경계 사례를 테스트합니다.
- 독후감 제한을 boolean으로 축소 → 편집을 시작할 때의 저장 이미지 출처를 기준값으로 보관하고, 정책에는 전체 이미지 수가 아니라 이번 편집에서 새로 추가된 이미지 수를 전달하는 판정을 둡니다. 직접 이미지·사진 메모 삽입과 최종 저장 모두 같은 판정을 사용하고, 기존 이미지 유지·교체는 통과하면서 신규 이미지 0개/한도 미만/한도 도달만 제한되는지 테스트합니다.

---

`flutter analyze`를 실행했습니다. 프로젝트 지침에 따라 테스트와 앱 실행은 수행하지 않았습니다.
