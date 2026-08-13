# 리뷰 결과

## 요약

- 상세·검색 화면의 새 레이아웃은 정적 분석을 통과했지만, 평점 스케일 불일치와 리뷰 미리보기의 접근 단절·허위 집계값 때문에 현재 상태로는 사용자에게 잘못된 정보를 보여준다.
- 검증: `flutter analyze`는 `No issues found`로 통과했고 `git diff --check`에서도 공백 오류가 없었다. 프로젝트 지침에 따라 앱 실행과 테스트는 수행하지 않았다.

## 문제점

- [문제][높음][데이터/평점 표시] `lib/features/book_detail/screens/book_detail_screen.dart:301`~`:309`와 `lib/features/book_search/screens/widgets/search_result_card.dart:81`~`:89`은 별 아이콘에는 10점 만점 원본을 `/2`한 `displayRating`을 넘기지만, 바로 옆 숫자에는 원본 `rating`을 표시한다. API 문서와 모델 주석상 원본은 0~10점이고 화면은 5점 만점이므로, 예를 들어 원본 8.0은 별 4개 옆에 `8.0`으로 표시되어 서로 모순된다.
- [문제][높음][데이터/리뷰 목록] `lib/features/book_detail/screens/widgets/community_reviews_section.dart:372`~`:392`는 API가 내려준 첫 페이지 최대 20건 중 3건만 렌더링하고 나머지를 `더보기` 뒤로 숨긴다. 그러나 `더보기`는 `:190`~`:196`에서 준비 중 SnackBar만 띄우며, 기존 상세 화면의 스크롤 알림도 제거되어 `ReviewsController.loadMore()`를 호출하는 경로가 전혀 없다. 따라서 4번째 리뷰부터는 이미 받은 항목조차 볼 수 없고 다음 커서 페이지에도 접근할 수 없다.
- [문제][중간][데이터/허위 개수] `lib/features/book_detail/screens/widgets/community_reviews_section.dart:40`~`:46`은 API나 상태에서 얻은 값이 아닌 고정값 `12`, `5`를 각각 독후감·주제 토론 개수로 사용자에게 표시한다. 해당 기능이 미구현이어도 실제 콘텐츠가 존재하는 것처럼 보이며, 책을 바꿔도 모든 상세 화면에서 같은 개수가 노출된다.
- [문제][중간][데이터/별점 집계] `lib/features/book_detail/screens/widgets/community_reviews_section.dart:200`~`:229`은 최신순 첫 페이지의 평점만 평균 내고 그 표본 수를 전체 평점처럼 표시한다. 리뷰 API 응답에는 전체 개수나 전체 평균이 없고 `hasNext`가 true일 수 있으므로, 오래된 리뷰가 더 있는 책에서도 최신 최대 20건의 편향된 평균과 개수만 아무 설명 없이 노출된다.
- [문제][중간][화면/메타데이터 회귀] 새 `_HeroSection`은 `lib/features/book_detail/screens/book_detail_screen.dart:251`~`:299`에서 출판사·쪽수·출간일만 한 줄로 조립하고 ISBN을 포함하지 않는다. 기존 `_MetaGrid`와 이관 기준 문서가 보장하던 ISBN 표시가 사라져, 사용자가 상세 화면에서 정확한 판본 식별자를 확인할 수 없다.

## 개선 제안

- 별 아이콘과 숫자에 서로 다른 평점 스케일 사용 → 상세와 검색 카드의 숫자도 `displayRating!.toStringAsFixed(1)`로 표시해 모두 5점 만점으로 통일한다.
- 3건 미리보기 뒤의 전체 리뷰 진입점이 미구현 → 전체 목록 화면을 구현해 첫 페이지 상태를 넘기고 커서 페이지네이션을 연결한다. 그 화면이 이번 범위가 아니라면, 동작하지 않는 `더보기`로 항목을 숨기지 말고 현재 받아온 리뷰를 계속 노출한다.
- 미연동 기능에 샘플 개수를 실제 값처럼 표시 → 집계 API/상태가 연결될 때까지 개수 배지를 숨기거나 `준비 중` 상태를 명시하고, 고정 샘플 값은 제품 UI에서 제거한다.
- 최신 첫 페이지를 전체 리뷰 집계처럼 표현 → 서버가 전체 평균·평점 수를 제공할 때만 요약을 표시한다. API 확장이 범위 밖이면 현재의 `_RatingSummary`를 제거해 부정확한 집계를 노출하지 않는다.
- 레이아웃 단순화 과정에서 ISBN 누락 → 새 히어로 메타 영역에 `ISBN ${detail.isbn}`을 별도 줄 또는 줄바꿈 가능한 메타 항목으로 복원한다.
