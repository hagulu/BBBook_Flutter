# 리뷰 결과

## 요약
- 강조 마크업의 저장·표시·`isImportant` 파생 흐름은 연결됐지만, 선택 영역을 교체 입력할 때 강조가 유실되고 IME 조합 표시가 사라지는 문제가 있어 편집 컨트롤러 보완이 필요하다.

## 문제점
- [중간][상태·데이터] `MemoHighlightController._applyTextDiff()`(`lib/features/book_memo/screens/widgets/highlight_text_field.dart:209-235`)는 교체 문자의 강조 여부를 항상 `deleteStart` 바로 앞 글자로 결정한다. 따라서 `::hl[[hello]]` 전체를 선택하면 버튼은 활성 상태로 표시되지만(`90-97`), 그 상태에서 `world`를 입력하면 선택된 강조 범위가 먼저 삭제되고 새 문자는 일반 텍스트로 추가되어 저장 결과가 `world`가 된다. 사용자가 보고 있던 활성 서식과 저장 데이터가 달라지며, 기존 강조를 수정하는 일반적인 입력만으로 `isImportant`까지 false로 바뀔 수 있다.
- [낮음][IME 렌더링] `buildTextSpan()`(`lib/features/book_memo/screens/widgets/highlight_text_field.dart:240-269`)은 `withComposing`과 `value.composing`을 사용하지 않는다. 강조가 하나라도 있는 순간부터 Flutter 기본 `TextEditingController`가 조합 중 범위에 제공하는 밑줄 표시가 사라져, 한글 등 IME 입력에서 아직 확정되지 않은 글자 범위를 사용자가 구분할 수 없다. 내부 range 보정은 조합 세션을 별도로 처리하지만 화면 표현은 그 상태를 반영하지 않는다.
- [낮음][접근성] 새 강조 도움말 `IconButton`은 `32×32`로 터치 영역을 강제한다(`lib/features/book_memo/screens/widgets/book_memo_item_sheet.dart:565-573`). 일반적인 최소 터치 영역인 `48×48`보다 작아 손가락 터치와 운동 보조 접근성에서 누르기 어렵다.
- [낮음][문서] 컨트롤러 주석 두 곳(`lib/features/book_memo/screens/widgets/highlight_text_field.dart:22,129`)과 `docs/file-index.md:67`이 `docs/policies/memo-highlight-toggle.md`를 구현 정책의 기준 문서로 참조하지만 해당 파일이 존재하지 않는다. 특히 자동 공백 삽입과 강조 내부 토글 차단처럼 비표준 동작의 근거를 코드 밖에서 확인하거나 다른 화면에 재사용할 수 없다.

## 개선 제안
- 강조 선택 영역 교체 → 텍스트 diff 적용 전에 `oldValue.selection`이 완전히 강조됐는지 캡처하고, 선택 교체 입력이면 그 상태를 새 문자 범위에 적용한다. 강조 전체 선택 후 교체, 일부 강조가 섞인 선택 후 교체 테스트를 추가한다.
- IME 조합 표시 누락 → 강조 span과 `value.composing` 범위를 함께 분할해 조합 구간에 기본 composing 밑줄을 합성하고, 강조 구간 안팎에서 조합할 때의 렌더링을 검증한다.
- 작은 도움말 터치 영역 → 시각 아이콘 크기는 유지하되 `IconButton` 제약을 최소 `48×48`로 확장한다.
- 존재하지 않는 정책 문서 → 실제 토글 정책 문서를 추가하거나, 별도 문서를 유지하지 않을 계획이면 코드 주석과 파일 인덱스의 참조를 제거해 문서 구조를 실제 파일과 일치시킨다.
