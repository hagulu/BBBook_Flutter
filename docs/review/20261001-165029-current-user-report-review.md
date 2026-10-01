# 리뷰 결과

## 요약
- 사용자 신고 API와 사유 선택 UI는 준비됐지만 두 화면 진입점에 연결되지 않아 신고할 수 없다. `flutter analyze`는 통과했다.

## 문제점
- [P1][작성자 프로필에서 사용자 신고에 진입할 수 없음] `lib/features/public_bookshelf/widgets/author_profile_sheet.dart:19-49`, `lib/features/public_bookshelf/widgets/user_report_flow.dart:22-39` — 작성자 탭 핸들러는 완독 책장이 공개된 경우에만 반환되고, 열린 시트에도 책장 이동 항목만 있다. 따라서 비공개 책장 작성자는 시트를 열 수 없고, 공개 책장 작성자도 신고 항목이 없어 새 `reportUser()`가 호출되지 않는다.
- [P1][공개 완독 책장에 사용자 신고 동작이 없음] `lib/features/public_bookshelf/screens/public_finished_bookshelf_screen.dart:83-91`, `lib/features/public_bookshelf/widgets/user_report_flow.dart:22-39` — 앱바에 신고 액션이 없고 화면 안에서도 `reportUser()`를 호출하지 않는다. 이 화면에 직접 들어온 사용자는 대상 사용자를 신고할 경로가 없다.

## 개선 제안
- 작성자 프로필의 신고 진입 누락 → 로그인 상태와 본인 여부로 신고 가능 여부를 판단하고, 책장 공개 여부와 독립적으로 작성자 시트를 열어 신고 항목을 제공한다. 항목 선택 시 `reportUser()`를 호출한다.
- 공개 완독 책장의 신고 동작 누락 → 신고 가능한 다른 사용자일 때 앱바에 신고 액션을 노출하고 `reportUser(context, widget.userId)`에 연결한다.
