# 리뷰 결과

## 요약
- 탭별 스크롤은 독립됐지만, 고정 헤더가 작은 세로 화면과 큰 글자 배율에서 본문을 밀어내는 레이아웃 회귀가 있다.

## 문제점
- [문제][중간][작은 세로 화면·큰 글자 배율에서 고정 영역이 `Column` 높이를 초과함] 책 정보 카드는 너비 84px인 2:3 표지 때문에 기본적으로 내부 높이 126px 이상이고, 카드·외부 패딩과 `TabBar`까지 모두 스크롤되지 않는 `Column` 자식이 됐다. 제목·저자·출판사 텍스트는 시스템 글자 배율에 따라 더 높아질 수 있으므로, 가로 모드나 화면 확대 환경에서는 이 고정 영역만 가용 높이를 넘겨 하단 `Expanded`가 0보다 작은 공간을 요구하고 `RenderFlex overflow`가 발생한다. 이전 `NestedScrollView`에서는 같은 헤더가 본문과 함께 스크롤되어 좁은 세로 공간에서도 탭 콘텐츠로 이동할 수 있었지만, 이제는 오버플로한 고정 헤더를 스크롤할 방법도 없다. (`lib/features/book_record/screens/book_record_screen.dart:133`, `lib/features/book_record/screens/book_record_screen.dart:139`, `lib/features/book_record/screens/book_record_screen.dart:153`, `lib/features/book_record/screens/book_record_screen.dart:171`, `lib/features/book_record/screens/book_record_screen.dart:628`, `lib/features/bookshelf/screens/widgets/book_cover.dart:33`)

## 개선 제안
- 고정 헤더의 세로 공간 초과 → 일반 높이에서는 현재 고정 배치를 유지하되, `LayoutBuilder`와 실제 텍스트 배율/가용 높이를 기준으로 공간이 부족할 때만 헤더를 접거나 스크롤 가능한 구조로 전환한다. 최소한 가로 모드와 큰 접근성 글자 배율에서도 탭 콘텐츠에 양의 높이가 남고 `RenderFlex overflow`가 발생하지 않는지 검증한다.
