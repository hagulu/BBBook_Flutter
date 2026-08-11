# 리뷰 결과

## 요약

- 카테고리 API의 경로·요청·응답 매핑은 문서와 일치하지만, 비동기 상태 표시와 다이얼로그의 반응형·접근성, 기능 간 의존 구조를 보완해야 한다.
- 검증: `flutter analyze`는 `No issues found`로 통과했다. 프로젝트 지침에 따라 앱 실행과 테스트는 수행하지 않았다.

## 문제점

- [문제][중간][상태/오류 처리] `lib/features/book_record/screens/widgets/book_info_edit_dialog.dart:219`~`:249`는 `categoriesAsync.valueOrNull`만 사용해 로딩과 오류를 모두 `categories == null`로 합친다. 이때 기존 책에 카테고리가 있어도 선택 필드는 `미지정`으로 표시되고 비활성화되며, API 요청이 실패한 경우 오류 안내나 재시도 수단 없이 화면을 나갈 때까지 카테고리를 수정할 수 없다. 저장 시 내부 `_selectedCategoryId`는 유지되어 표시 내용과 실제 전송 값도 서로 달라진다.
- [문제][중간][접근성] `lib/features/book_record/screens/widgets/book_info_edit_dialog.dart:290`~`:307`은 기존 `InputDecoration.labelText`를 별도의 `Text` 위젯으로 옮기고 실제 `TextField`에는 라벨·힌트·시맨틱 이름을 남기지 않았다. 스크린 리더가 편집 컨트롤만 순회하면 제목·저자·출판사·총 쪽수 입력창을 서로 구분할 수 없다.
- [문제][중간][렌더링/텍스트 배율] `lib/features/book_record/screens/widgets/book_info_edit_dialog.dart:320`~`:363`은 92dp 표지, 32dp 간격, 고정 패딩과 텍스트를 가진 작업 버튼 열을 모두 비유연한 `Row`에 배치한다. 기본 `Dialog`의 좌우 inset과 내부 24dp 패딩을 적용하면 320dp 화면의 실제 콘텐츠 폭은 약 192dp인데, 이 행의 최소 폭은 그보다 커서 overflow할 수 있다. 더 넓은 화면에서도 텍스트 배율을 높이면 작업 버튼의 고유 폭이 커져 같은 문제가 발생한다.
- [문제][중간][구조] `lib/features/bookshelf/screens/widgets/reading_tab_view.dart:5`와 `:43`~`:59`는 책장 UI가 `book_record` 기능의 provider를 직접 가져오도록 바뀌었다. 반대로 해당 provider는 이미 `bookshelf`의 repository/provider에 의존하므로, 카테고리 색상이라는 공용 마스터 데이터 때문에 두 기능의 의존 방향이 뒤섞였다. `BookCategory` 주석도 책 정보 수정과 서재 필터에서 공용으로 쓴다고 명시하고 있어 `book_record` 내부 소유로 두면 이후 사용처마다 같은 역방향 의존이 늘어난다.
- [문제][낮음][데이터 요청] `lib/features/book_record/providers/book_record_providers.dart:206`~`:210`은 자주 바뀌지 않는 정적 목록을 `autoDispose`로 선언하고, `lib/features/book_record/screens/book_record_screen.dart:530`~`:539`와 `lib/features/bookshelf/screens/widgets/reading_tab_view.dart:49`~`:59`는 실제 카테고리가 없는 책에서도 이를 무조건 구독한다. 구독자가 모두 사라질 때 캐시가 폐기되므로 화면을 다시 구성할 때 동일한 전체 목록을 재요청하고, 카테고리 배지가 필요 없는 화면 방문에도 요청이 발생한다.

## 개선 제안

- 카테고리 로딩·오류·값 없음이 모두 `미지정`으로 표시됨 → `AsyncValue`의 loading/error/data를 구분해 로딩 표시와 오류·재시도 UI를 제공하고, 로딩 중에는 `widget.book.category`를 사용해 현재 선택을 정확히 보여준다.
- 시각적 라벨과 입력 컨트롤의 접근성 이름이 분리됨 → 외부 라벨 디자인은 유지하되 각 `TextField`에 해당 라벨을 포함한 `Semantics`를 연결하거나, 시맨틱에 남는 `labelText` 구조를 사용한다.
- 고정 폭 요소를 한 행에 배치함 → 가용 폭과 텍스트 배율에 따라 `Wrap`/세로 배치로 전환하거나 작업 버튼 영역을 `Flexible`로 만들어 좁은 화면에서도 수평 overflow가 발생하지 않게 한다.
- 책장 기능이 책 기록 provider를 역참조함 → 카테고리 모델·API·provider를 두 기능이 함께 참조할 수 있는 중립적인 기능/공용 데이터 계층으로 옮기고, 각 feature는 그 계층만 의존하게 한다.
- 정적 목록을 조건 없이 구독하고 화면 이탈 시 폐기함 → 앱 범위에서 작은 카테고리 목록을 캐시하고, 색상이 필요한 `displayCategoryId`가 있을 때만 조회하도록 구독 위치를 상위에서 조정한다.
