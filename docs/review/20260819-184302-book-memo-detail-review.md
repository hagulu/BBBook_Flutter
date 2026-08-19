# 리뷰 결과

## 요약
- 메모 조각 액션 시트(복사/수정/삭제)와 타임라인 카드 UI 개편은 구조·로직상 문제 없이 잘 구현됐으나, 무관해 보이는 정책 문서 삭제로 `docs/file-index.md`가 존재하지 않는 파일을 참조하게 됐다.

## 문제점
- [문제] `docs/policies/memo-highlight-toggle.md`가 삭제됐지만, 이 문서가 기준으로 삼는 구현체 `lib/features/book_memo/screens/widgets/highlight_text_field.dart`는 그대로 남아 있고, 이번 diff의 실제 작업 범위(조각 액션 시트, 복사 기능, 타임라인 카드 레이아웃 개편)와도 무관하다. `docs/file-index.md:69`는 여전히 이 문서를 가리키고 있어 삭제가 반영되지 않은 채로 남으면 인덱스가 깨진 링크를 갖게 된다.
- [문제] `_MemoItemActionSheet`가 `lib/features/book_record/screens/widgets/record_dialog_shell.dart`를 임포트해 사용한다. 이 파일은 자체 문서 주석에 "책 기록 화면의 커스텀 폼형 팝업이 공유하는 바텀시트 뼈대"로 book_record 기능 전용임을 명시하고 있는데, 이번 변경으로 book_memo 기능에서도 재사용되면서 `structure` 스킬이 정한 기능 경계(`lib/features/<feature>` 내부 위젯은 해당 기능 전용, 기능 간 공유 위젯은 `lib/shared/widgets/`)와 어긋난다.

## 개선 제안
- 정책 문서 삭제가 의도한 것인지 확인한다. 의도한 삭제라면 `docs/file-index.md:69` 항목도 함께 제거하고, 실수라면 문서를 복원한다.
- `RecordDialogShell`을 두 기능(book_record, book_memo)이 함께 쓰는 상태이므로 `lib/shared/widgets/`로 이동하고, 주석의 "책 기록 화면 전용" 문구도 공용 컴포넌트에 맞게 수정한다.
