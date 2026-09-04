# 리뷰 결과

## 요약
- `flutter analyze`는 통과했지만, 검색 디바운스 중 이전 요청이 새 입력과 경합하는 문제와 댓글 삭제 후 유효 범위를 벗어난 마지막 페이지에 고립되는 문제가 있습니다.

## 문제점
- [문제] [보통] `lib/features/book_search/providers/book_search_providers.dart:116`은 새 검색어가 입력되어도 타이머만 교체하고 현재 진행 중인 요청의 `_requestId`를 무효화하지 않습니다. 예를 들어 `A` 검색 요청 중 `B`를 입력했을 때 `A` 응답이 600ms 디바운스 안에 도착하면 `lib/features/book_search/providers/book_search_providers.dart:175`의 검사에 통과해 검색창은 `B`인데 `A` 결과가 반영됩니다. `B` 요청이 시작되기 전에는 이 결과가 흐림·터치 차단 상태도 아니어서 잘못된 책 상세를 열 수 있고, 화면 끝에 있으면 `A`의 다음 페이지 요청까지 시작될 수 있습니다. 추가된 요청 경합 테스트는 두 요청을 모두 `search()`로 즉시 시작하므로 이 디바운스 구간을 검증하지 못합니다.
- [문제] [보통] `lib/features/profile/providers/my_content_providers.dart:280`은 상세에서 돌아올 때 기존 서버 페이지를 그대로 재조회합니다. 마지막 페이지의 마지막 댓글을 상세에서 삭제하면 전체 페이지 수가 하나 줄어 기존 페이지가 범위를 벗어날 수 있으며, 이때 일반적인 페이지 응답은 `items`가 비고 `totalPages`는 줄어든 상태가 됩니다. 그러나 `lib/features/profile/screens/my_discussion_answers_screen.dart:97`은 빈 `items`만 보고 페이지네이션까지 제거해 "작성한 토론 댓글이 없습니다"만 표시하므로, 이전의 유효 페이지로 이동할 방법이 없습니다.
- [문제] [낮음] `docs/file-index.md:42`는 `my_content_api.dart`가 토론 댓글까지 포함한 4개 목록을 모두 커서로 조회한다고 설명하지만, 이번 변경으로 토론 댓글은 `page`/`totalPages` 기반 조회가 되었습니다. 구조 파악의 기준 문서와 실제 API 구현이 서로 다릅니다.

## 개선 제안
- 디바운스 중 이전 요청 경합 → 새 비어 있지 않은 입력을 받는 즉시 현재 요청 세대를 무효화하고 새 검색이 대기 중임을 상태로 표현해 기존 결과의 추가 로드와 탭을 막습니다. 느린 `search('A')` 실행 중 `onQueryChanged('B')`를 호출하고 `B` 디바운스가 끝나기 전에 `A`를 완료시키는 테스트도 추가합니다.
- 삭제 후 범위를 벗어난 페이지 → 재조회 결과가 비었고 `totalPages > 0`이며 요청 페이지가 `totalPages` 이상이면 새 마지막 페이지(`totalPages - 1`)를 한 번 다시 조회합니다. 빈 상태는 `totalElements == 0`일 때만 표시하고, 이 경계 동작을 provider 테스트로 고정합니다.
- 파일 인덱스 불일치 → `my_content_api.dart` 설명을 독후감·리뷰·토론은 커서, 토론 댓글은 페이지 번호 기반 조회라고 수정합니다.
