# 리뷰 결과

## 요약
- `flutter analyze`는 통과했고 검색 결과 누적·추가 로드 실패 상태는 분리되어 있지만, 첫 페이지가 화면을 채우지 못하면 이후 결과에 접근할 수 없고 추가 로드 오류 행은 큰 글자에서 가로 오버플로할 수 있습니다.

## 문제점
- [문제] [보통] `lib/features/book_search/screens/book_search_screen.dart:45`는 `ScrollController`의 위치 변경 리스너에서만 `loadMore()`를 호출합니다. 첫 10개 결과의 전체 높이가 목록 뷰포트보다 작으면 `maxScrollExtent`가 0인 채로 위치가 변하지 않으며, 특히 Android의 기본 clamping 스크롤에서는 끝 방향으로 드래그해도 컨트롤러 리스너가 호출되지 않습니다. 이 경우 `lib/features/book_search/providers/book_search_providers.dart:45`의 `hasMore`가 참이어도 다음 페이지를 요청할 경로가 없어, 세로로 긴 태블릿·데스크톱 화면에서는 검색 결과가 첫 페이지에서 끊깁니다.
- [문제] [낮음] `lib/features/book_search/screens/book_search_screen.dart:329`의 추가 로드 오류 UI는 긴 안내 문구와 `TextButton`을 한 줄 `Row`에 배치하지만 어느 쪽에도 `Flexible`이나 줄바꿈 제약이 없습니다. 좁은 화면이나 큰 시스템 글자 배율에서는 두 자식의 합산 너비가 목록 폭을 넘어 `RenderFlex overflow`가 발생하고 재시도 버튼이 잘릴 수 있습니다.

## 개선 제안
- 첫 페이지가 화면을 채우지 못하는 경우 → 결과 렌더링 후 `ScrollMetrics`를 확인해 `hasMore && maxScrollExtent <= 0`이면 다음 페이지를 이어서 요청하고, 목록이 스크롤 가능해지거나 마지막 페이지에 도달할 때까지 같은 검사를 반복합니다. 일반 스크롤에서는 현재의 끝 도달 조건을 유지합니다.
- 추가 로드 오류 행 오버플로 → 안내 문구를 `Flexible`로 감싸고 줄바꿈을 허용하거나, `Wrap`/`Column`으로 문구와 재시도 버튼이 좁은 폭·큰 글자에서도 재배치되게 합니다.
