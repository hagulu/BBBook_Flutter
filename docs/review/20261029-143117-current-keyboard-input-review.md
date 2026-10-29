# 리뷰 결과

## 요약

- 현재 미커밋 변경분인 iOS 숫자 키패드 완료 바·태그 연속 입력과 추천 목록·좁은 화면 표시 조정을 검토했으며, 완료 바와 기존 입력 화면의 연동에서 P2 문제 2건을 확인했습니다.
- 범위: 변경된 Dart 파일 9개와 신규 `lib/shared/widgets/keyboard_done_bar.dart`, 관련 공통 시트·상태 관리·Flutter SDK 구현.
- `flutter analyze` 통과(`No issues found!`). 앱 실행과 테스트는 프로젝트 지침에 따라 수행하지 않았으며, 아래 판단은 정적 코드 검토에 근거합니다.
- 이전 카메라 리뷰의 원본 덮어쓰기 문제는 현재 HEAD에서 별도 임시 파일 저장 후 교체하는 방식으로 수정되어 있습니다. 이번 문제 건수에는 포함하지 않았습니다.

## 문제점

- [P2] 진행률 입력에서 새 완료 버튼을 누르면 입력값이 저장되지 않고 취소됩니다.
  - 위치: [keyboard_done_bar.dart:40](../../lib/shared/widgets/keyboard_done_bar.dart#L40), 적용부 [progress_card.dart:184](../../lib/features/book_record/screens/widgets/progress_card.dart#L184).
  - 조건: iOS에서 책의 현재 쪽수 또는 오디오북 진행률을 직접 입력하고 키보드 위의 새 “완료” 버튼을 누릅니다.
  - 근거: 완료 버튼은 `primaryFocus?.unfocus()`만 호출합니다. 진행률은 `TextField.onSubmitted`에서만 `_commitPage()`로 적용하고(196행), 제출 없이 포커스를 잃으면 `_onFocusChanged()`가 `_committedPage`로 되돌립니다(101~115행). 포커스 해제 자체는 제출 액션을 실행하지 않습니다. Flutter의 제출 처리는 입력 액션에 따른 별도 콜백입니다. [Flutter `TextField.onSubmitted` 문서](https://api.flutter.dev/flutter/material/TextField/onSubmitted.html).
  - 영향: 예를 들어 현재 10쪽인 책에 20을 입력하고 완료를 눌러도 10쪽으로 돌아갑니다. 새 버튼이 iOS 숫자 키패드의 완료 동작을 대신하지 못합니다.

- [P2] 메모 쪽수 입력 시 완료 바가 입력란을 덮습니다.
  - 위치: [keyboard_done_bar.dart:35](../../lib/shared/widgets/keyboard_done_bar.dart#L35), 적용부 [book_note_memo_sheet.dart:1021](../../lib/features/book_note/screens/widgets/book_note_memo_sheet.dart#L1021).
  - 조건: iOS 메모 작성·수정 화면에서 하단 툴바의 시작 또는 끝 쪽수 입력란에 포커스를 둡니다.
  - 근거: 완료 바는 루트 `Overlay`에서 키보드 바로 위에 높이 44px로 표시됩니다. 반면 메모 화면은 기본 `Scaffold`의 키보드 회피 동작을 사용하며, 본문 `Column`의 마지막 자식인 `_EditorToolbar`도 키보드 바로 위에 배치됩니다(649~679행). 완료 바 높이를 위한 추가 여백은 없습니다. 툴바는 48px 행과 위아래 10px 패딩으로 구성되고(892~996행), 쪽수 필드가 그 행 중앙에 있으므로 완료 바가 필드 하단과 입력 텍스트 영역을 가립니다. 이 겹침은 현재 레이아웃 구조에서 도출한 결과입니다. [Flutter `Scaffold.resizeToAvoidBottomInset` 문서](https://api.flutter.dev/flutter/material/Scaffold/resizeToAvoidBottomInset.html), [Flutter `OverlayEntry` 문서](https://api.flutter.dev/flutter/widgets/OverlayEntry-class.html).
  - 영향: 입력 중인 쪽수를 읽기 어렵고, 옆 쪽수 필드로 이동하는 터치도 완료 바에 가로막힙니다. 포커스된 입력창의 스크롤 여백만 늘려도 고정된 하단 툴바의 위치는 바뀌지 않습니다.

## 개선 제안

- 완료 버튼의 포커스 해제만 수행 → `KeyboardDoneBar`에 완료 콜백을 제공하고 진행률 입력에서는 `_commitPage()`를 연결하세요. 값 적용을 먼저 수행한 뒤 포커스를 해제해야 하며, 일반적인 포커스 이탈 시 입력 취소 정책은 유지할 수 있습니다.
- 완료 바와 메모 툴바의 영역 겹침 → 숫자 입력 중에는 완료 바 높이만큼 툴바 아래에 공간을 확보하거나, 완료 버튼을 툴바 레이아웃 안에 배치하세요. 시작·끝 쪽수와 완료 버튼이 동시에 보이고 눌릴 수 있어야 합니다.
