# 리뷰 결과

## 요약

- 현재 메모 작성 UI 변경에서 글자 수 계산 불일치와 발췌 OCR 버튼의 작은 터치 영역 2건을 확인했다. `flutter analyze`는 통과했다.

## 문제점

- [P2][AI 메모 글자 수 제한과 생성 조건이 다름] `lib/features/book_note/screens/widgets/book_note_ai_memo_composer_screen.dart:40-45`, `lib/features/book_note/screens/widgets/book_note_ai_memo_composer_screen.dart:125`, `lib/features/book_note/screens/widgets/book_note_ai_memo_composer_screen.dart:149-153` — Flutter `TextField.maxLength`는 사용자에게 보이는 글자 단위로 제한하지만 생성 가능 여부와 새 카운터는 UTF-16 코드 단위인 `String.length`를 사용한다. 이모지 1,501개는 입력창의 3,000자 제한 안에 있지만 화면에는 `3,002 / 3,000`으로 표시되고 생성 버튼이 비활성화된다.
- [P3][빠른 발췌 OCR 버튼의 터치 영역이 28×28dp] `lib/features/book_note/screens/widgets/book_note_memo_sheet.dart:223-244` — 새 카메라 버튼에 `BoxConstraints.tightFor(width: 28, height: 28)`을 지정해 실제 누를 수 있는 영역이 작다. 입력창 안에서 커서를 놓으려는 터치와 구분하기 어렵고 손가락이나 접근성 입력으로 누르기 힘들 수 있다.

## 개선 제안

- AI 메모 글자 수 제한과 생성 조건이 다름 → 입력 제한·카운터·생성 조건을 같은 글자 수 기준(`characters.length`)으로 계산한다.
- 빠른 발췌 OCR 버튼의 터치 영역이 28×28dp → 아이콘 크기는 유지하고 버튼의 터치 영역을 최소 44–48dp로 넓힌다.

검증: `flutter analyze` 통과. 프로젝트 지침에 따라 앱과 테스트는 실행하지 않았다.
