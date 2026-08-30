# 리뷰 결과

## 요약
- `flutter analyze`는 통과했지만, 독자평 목록의 추가 로딩·공감 비동기 경합 2건과 커뮤니티 미리보기의 중복 API 요청 1건을 보완할 필요가 있다.

## 문제점
- [문제][중간][추가 로딩 중 새로고침이 실패하면 목록이 영구적으로 추가 로딩 상태에 머묾] `loadMore()`는 요청 전에 `isLoadingMore`를 `true`로 바꾸고, `_reloadFirstPage()`는 조회 성공 여부와 무관하게 세대값을 올린다. 이때 당겨서 새로고침 요청이 실패하면 기존 목록을 그대로 유지하므로 `isLoadingMore`도 `true`로 남고, 먼저 진행 중이던 추가 로딩은 세대가 달라졌다는 이유로 성공·실패 경로 모두 상태 복구 없이 반환한다. 이후 `loadMore()` 진입 조건이 계속 차단되어 화면 하단 로더가 사라지지 않고 다음 페이지도 더는 불러올 수 없다. (`lib/features/book_detail/providers/book_detail_providers.dart:122`, `lib/features/book_detail/providers/book_detail_providers.dart:127`, `lib/features/book_detail/providers/book_detail_providers.dart:133`, `lib/features/book_detail/providers/book_detail_providers.dart:145`, `lib/features/book_detail/providers/book_detail_providers.dart:260`, `lib/features/book_detail/providers/book_detail_providers.dart:269`)
- [문제][중간][공감 버튼을 연속으로 누르면 마지막 사용자 입력과 서버·화면 상태가 달라질 수 있음] 전체 목록은 리뷰별 공감 요청이 진행 중인지 추적하지 않고 버튼을 계속 활성화하며, `toggleLike()`는 호출 시 전달된 `review.isLiked`를 기준으로 낙관적 상태와 완료 상태를 각각 덮어쓴다. 같은 리뷰의 POST/DELETE가 겹치면 서버 처리 순서와 응답 도착 순서에 따라 이전 요청의 응답이 최신 의도를 덮어쓸 수 있고, 아주 빠른 두 번 탭에서는 동일한 이전 콜백이 두 번 실행되어 두 번째 탭이 취소가 아닌 중복 POST가 될 수도 있다. (`lib/features/book_detail/screens/book_review_list_screen.dart:60`, `lib/features/book_detail/screens/book_review_list_screen.dart:213`, `lib/features/book_detail/providers/book_detail_providers.dart:230`, `lib/features/book_detail/providers/book_detail_providers.dart:243`)
- [문제][낮음][미리보기 하나를 표시할 때 동일한 개수를 위해 API를 중복 호출하고 한 요청 실패가 전체 영역을 숨김] API 문서상 `community-preview` 응답은 최근 독자평뿐 아니라 공개 독후감 개수와 열린 토론 개수도 함께 반환한다. 현재 모델은 이 두 값을 파싱하지 않고, 컨트롤러가 같은 집계값을 주는 `community-counts`를 추가 호출한다. 두 요청을 `Future.wait()`로 묶었기 때문에 모든 진입 화면에서 불필요한 요청이 하나씩 늘고, 미리보기 응답이 정상이어도 개수 요청 하나만 실패하면 사용 가능한 독자평과 진입 버튼까지 전부 오류 상태로 사라진다. (`lib/features/book_community/models/book_community.dart:64`, `lib/features/book_community/data/book_community_api.dart:37`, `lib/features/book_community/providers/book_community_providers.dart:30`)

## 개선 제안
- 추가 로딩과 실패한 새로고침 경합 → 첫 페이지 재조회가 기존 추가 로딩을 무효화할 때 `isLoadingMore`를 명시적으로 해제하거나, 재조회 실패 시 기존 추가 로딩 세대를 계속 유효하게 두어 그 요청이 정상적으로 상태를 마무리하게 한다. 성공·실패·세대 불일치 모든 경로에서 로딩 플래그가 종료된다는 테스트를 추가한다.
- 독자평 공감 연속 요청 → 리뷰 ID별 요청 진행 상태를 두고 완료 전 버튼을 비활성화하거나, 최신 목표 상태를 보관한 직렬화 큐로 POST/DELETE를 순서대로 처리해 이전 응답이 최신 의도를 덮어쓰지 못하게 한다.
- 커뮤니티 미리보기 중복 요청 → `BookCommunityPreview`가 응답의 `reflections.count`와 `discussions.count`를 함께 파싱하도록 하고 이 화면에서는 `community-preview` 한 번만 호출한다. 개수 전용 화면이 생길 때만 `community-counts`를 별도로 사용한다.
