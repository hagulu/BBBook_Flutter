# 리뷰 결과

## 요약
- 현재 미커밋 변경사항 전체와 새 `book_record_tab_view.dart`를 검토했다. UI 변경에서 수정이 필요한 문제 2건(P1 1건, P2 1건)을 확인했다.
- `flutter analyze`는 통과했다. 프로젝트 지침에 따라 앱과 테스트는 실행하지 않았으며, 아래 레이아웃 문제는 호출부 및 설치된 Flutter·Quill 렌더링 코드를 대조해 확인했다. 탭 전환·관성 스크롤·키보드 동작의 실행 검증은 남아 있다.

## 문제점

### [P1] 이미지가 있는 독후감에 intrinsic 측정을 적용하지 마세요 — lib/features/book_reflection/screens/book_reflection_editor_screen.dart:640

기존 이미지가 포함된 독후감의 수정 화면을 열면 `SliverFillRemaining(hasScrollBody: false)`가 편집기의 intrinsic 높이를 측정한다. 이 호출은 Quill의 `RenderEditor` → `RenderEditableTextLine` → `RenderParagraph`를 거쳐 이미지 WidgetSpan의 dry layout 계산으로 이어지는데, `ReflectionImageEmbedBuilder.build()`가 반환하는 `LayoutBuilder`는 이 계산을 지원하지 않는다. 따라서 debug 빌드에서 레이아웃 예외가 발생한다. release에서는 해당 측정이 `Size.zero`를 반환하므로 이미지 높이가 슬리버 크기에 제대로 반영되지 않아 긴 이미지 문서의 본문이 넘치고 끝까지 스크롤되지 않을 수 있다. 신규 이미지 첨부를 막는 현재 정책과 별개로 기존 이미지는 편집기에 그대로 로드되므로 실제 수정 경로에 영향을 준다. 종전 `SingleChildScrollView` 구조에는 이 intrinsic 측정이 없었다.

### [P2] 긴 독후감을 작성할 때도 저장 버튼을 고정하세요 — lib/features/book_reflection/screens/book_reflection_editor_screen.dart:617

저장 버튼이 `pinned: false`인 `SliverAppBar` 안으로 이동하여 본문을 아래로 스크롤하면 사라진다. Quill의 커서 추적도 같은 `_editorScrollController`를 움직이므로 긴 문서를 입력하는 중에 자동으로 저장 액션이 화면 밖으로 밀려난다. 저장 버튼은 이 앱바에만 있어 작성하던 위치에서 바로 저장할 수 없고 문서 맨 위까지 되돌아가야 한다. 기존 고정 `AppBar`에서는 발생하지 않던 편집 동작의 회귀이며, 이전 리뷰에서 지적된 상태가 유지되고 있다.

## 개선 제안
- 이미지 문서의 높이 측정 오류 → 편집 본문은 `SliverToBoxAdapter` 또는 기존 `SingleChildScrollView`처럼 자식의 실제 레이아웃으로 높이를 결정하는 구조를 사용한다. 빈 편집 영역의 최소 높이가 필요하면 intrinsic 측정 없이 별도로 확보한다.
- 저장 액션 접근성 → 일반 `AppBar`로 저장 버튼을 고정하거나, 현재 구조를 유지하면서 `SliverAppBar.pinned`를 `true`로 설정한다.
- 후속 검증 시에는 기존 이미지가 포함된 긴 독후감의 수정 진입·마지막 문단 접근, 키보드가 열린 긴 문서의 저장 버튼 접근, 길이가 다른 책 기록 탭 간 전환을 우선 확인한다.
