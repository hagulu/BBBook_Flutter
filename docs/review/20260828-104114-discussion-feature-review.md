# 리뷰 결과

## 요약
- 토론 목록·상세·작성 흐름과 API 계약은 대체로 맞지만, 답변 중복 등록 가능성 1건과 상태 최신성·표시 정확성·접근성 문제 3건을 보완해야 한다.

## 문제점
- [문제][높음][답변 작성 성공을 실패로 오인해 중복 등록 가능] `submit()`은 답변 생성 POST가 성공한 뒤 첫 페이지 GET까지 한 작업으로 묶어 기다린다. POST 이후 `_reloadFirstPageKeepingRest()`의 GET만 일시적으로 실패해도 예외가 호출부까지 전달되고, 상세 화면은 작성 폼과 입력 내용을 그대로 둔 채 오류를 표시한다. 사용자가 등록을 다시 누르면 이미 저장된 같은 답변이 한 번 더 생성된다. (`lib/features/discussion/providers/discussion_providers.dart:282`, `lib/features/discussion/providers/discussion_providers.dart:287`, `lib/features/discussion/providers/discussion_providers.dart:293`, `lib/features/discussion/providers/discussion_providers.dart:377`, `lib/features/discussion/screens/discussion_detail_screen.dart:95`, `lib/features/discussion/screens/discussion_detail_screen.dart:103`)
- [문제][중간][토론 상태 변경 성공 후 화면이 이전 상태에 머묾] 닫기·다시 열기·마감일 변경은 변경 API 뒤에 `reload()`를 호출하지만, `reload()`가 모든 조회 오류를 삼킨다. 따라서 변경 API는 성공하고 후속 GET만 실패해도 각 액션은 성공으로 반환된다. 로딩이나 마감일 팝업은 정상 종료되지만 화면은 여전히 답변 작성·수정이 가능한 열린 상태로 보이거나, 이전 마감일·닫힘 상태를 계속 표시한다. (`lib/features/discussion/providers/discussion_providers.dart:147`, `lib/features/discussion/providers/discussion_providers.dart:157`, `lib/features/discussion/providers/discussion_providers.dart:162`, `lib/features/discussion/providers/discussion_providers.dart:167`, `lib/features/discussion/screens/discussion_detail_screen.dart:199`, `lib/features/discussion/screens/discussion_detail_screen.dart:214`)
- [문제][중간][책 상세의 토론 개수가 항상 샘플 값으로 노출됨] 실제 토론 목록으로 이동하는 버튼을 연결했지만 배지에는 데이터와 무관하게 `discussionCount: 5`가 전달된다. 토론이 한 건도 없거나 5건보다 많아도 항상 `5개`로 보여 사용자에게 잘못된 정보를 제공하며, 같은 영역의 독후감도 `12개`로 고정되어 있다. (`lib/features/book_detail/screens/widgets/community_reviews_section.dart:49`, `lib/features/book_detail/screens/widgets/community_reviews_section.dart:54`, `lib/features/book_detail/screens/widgets/community_reviews_section.dart:55`, `lib/features/book_detail/screens/widgets/community_reviews_section.dart:330`)
- [문제][낮음][아이콘 액션의 터치 영역이 32px로 축소됨] 선택지 이동·삭제, 토론/답변 신고처럼 정확한 조작이 필요한 아이콘 버튼의 최소 영역을 `32x32`로 덮어써 Flutter 기본 터치 영역보다 작게 만든다. 인접한 이동·삭제 버튼은 특히 오조작하기 쉽고 운동 보조가 필요한 사용자의 접근성이 떨어진다. (`lib/features/discussion/screens/widgets/discussion_options_editor.dart:196`, `lib/features/discussion/screens/widgets/discussion_options_editor.dart:204`, `lib/features/discussion/screens/widgets/discussion_answer_item.dart:156`, `lib/features/discussion/screens/discussion_detail_screen.dart:495`)

## 개선 제안
- 답변 작성 후 재조회 실패 → 생성 POST의 성공 여부와 목록 갱신 결과를 분리한다. POST가 성공하면 작성 폼을 닫고 중복 제출을 막은 뒤, 응답으로 새 항목을 반영하거나 별도 invalidate/재시도로 목록만 최신화한다.
- 토론 상태 변경 후 재조회 실패 → 닫기·재열기·마감일 API 응답을 모델로 파싱해 즉시 상태에 반영하거나, 후속 조회 실패를 액션 성공과 구분해 화면을 명시적으로 재조회 상태로 전환한다. 최소한 이전 상태를 성공한 것처럼 계속 노출하지 않도록 한다.
- 샘플 개수 노출 → 전체 개수를 제공하는 계약이 연결되기 전에는 개수 텍스트를 숨긴다. 전체 개수가 필요하면 목록의 현재 로드 건수가 아니라 서버가 제공하는 `totalCount`를 사용한다.
- 작은 아이콘 터치 영역 → 시각적 아이콘 크기는 유지하되 `IconButton`의 최소 터치 영역을 48px 수준으로 복원하고, 선택지 이동·삭제 버튼 사이에 충분한 간격과 의미 라벨을 제공한다.
