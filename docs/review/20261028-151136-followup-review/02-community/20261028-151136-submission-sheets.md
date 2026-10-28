# 리뷰 결과

## 요약

독자평은 이제 요청 실패 시 작성 내용을 유지하며, 독자평·토론 답변에 전송 중 뒤로 가기 방어가 추가됐습니다. 다만 **시트 드래그 닫기**와 **독자평 전송 중 추가 편집**은 아직 입력을 잃거나 처리 결과를 혼동하게 할 수 있습니다. P2 2건입니다.

## 문제점

### [FUP-03][P2] PopScope만으로는 전송 중 시트의 아래로 끌어 닫기를 막지 못함

**위치**

- [lib/features/book_detail/screens/widgets/review_edit_dialog.dart:33](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_detail/screens/widgets/review_edit_dialog.dart:33) 및 [lib/features/book_detail/screens/widgets/review_edit_dialog.dart:46](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_detail/screens/widgets/review_edit_dialog.dart:46): 작성·수정 시트의 `showModalBottomSheet`는 기본 드래그를 허용합니다.
- [lib/features/book_detail/screens/widgets/review_edit_dialog.dart:110](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_detail/screens/widgets/review_edit_dialog.dart:110): child의 `PopScope`만으로 전송 중 닫기를 막습니다.
- [lib/features/discussion/screens/widgets/discussion_answer_composer.dart:21](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/discussion/screens/widgets/discussion_answer_composer.dart:21) 및 [lib/features/discussion/screens/widgets/discussion_answer_composer.dart:91](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/discussion/screens/widgets/discussion_answer_composer.dart:91): 토론 답변도 같은 구성이며 전송 중 전체 입력을 막는 오버레이는 없습니다.

**근거**

설치된 Flutter 소스의 [bottom_sheet.dart:1303](/Users/hagulu/develop/framework/flutter/packages/flutter/lib/src/material/bottom_sheet.dart:1303)에서 `enableDrag` 기본값은 true입니다. 같은 파일 [771행](/Users/hagulu/develop/framework/flutter/packages/flutter/lib/src/material/bottom_sheet.dart:771)의 드래그 닫기는 `Navigator.pop(context)`를 직접 호출합니다. [NavigatorState.pop:5606](/Users/hagulu/develop/framework/flutter/packages/flutter/lib/src/widgets/navigator.dart:5606)은 `maybePop`의 `popDisposition` 검사 경로를 거치지 않으므로 자식 `PopScope(canPop:false)`만으로 이 닫기를 막을 수 없습니다.

**발생 조건·영향**

느린 통신에서 등록/저장을 누른 직후 시트 상단을 아래로 끌면 시트가 닫히고 요청은 계속 진행됩니다. 실패하면 보존하려던 입력이 사라지고, 성공하면 사용자는 닫기를 취소로 이해한 채 다시 등록할 수 있습니다. 특히 여러 답변을 허용하는 토론에서는 중복 답변으로 이어질 수 있습니다.

직접 책 등록 시트에는 `AppLoading`의 전역 터치 차단이 함께 있어 동일한 드래그 누락으로 분류하지 않았습니다. 전체 화면 토론 작성 폼의 일반 뒤로 가기 방어도 이번 지적 대상이 아닙니다.

### [FUP-04][P2] 전송 중 변경한 독자평 입력이 저장되지 않은 채 성공 시 사라짐

**위치**

- [lib/features/book_detail/screens/widgets/review_edit_dialog.dart:81](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_detail/screens/widgets/review_edit_dialog.dart:81): 전송할 본문·별점·스포일러 상태는 저장 시작 시 캡처됩니다.
- [lib/features/book_detail/screens/widgets/review_edit_dialog.dart:128](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_detail/screens/widgets/review_edit_dialog.dart:128): 별점과 스포일러 콜백은 `_isSubmitting`일 때도 동작합니다.
- [lib/features/book_detail/screens/widgets/review_edit_dialog.dart:139](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_detail/screens/widgets/review_edit_dialog.dart:139): TextField에도 전송 중 `readOnly`·`enabled` 처리가 없습니다.
- [lib/features/book_detail/screens/widgets/review_edit_dialog.dart:99](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/book_detail/screens/widgets/review_edit_dialog.dart:99): 이전 입력의 요청이 성공하면 현재 폼 내용을 확인하지 않고 닫습니다. 저장 버튼만 비활성화됩니다.

**발생 조건·영향**

독자평 A를 등록한 뒤 응답을 기다리는 동안 오타를 고쳐 B로 바꾸거나 스포일러를 켭니다. UI는 변경을 받아들이지만 요청은 A를 전송한 상태입니다. 잠시 후 A의 저장 성공으로 시트가 닫혀 B는 남지 않습니다. 특히 전송 중이라는 문구 외에는 입력 제한이 없어 수정 가능 상태로 보입니다. 이번에 요청 완료까지 시트를 유지하도록 바뀌면서 생긴 입력 상태 문제입니다.

## 개선 제안

- FUP-03: 이 두 종류의 시트에서 드래그 닫기를 끄거나, 전송 상태를 실제 시트 드래그 처리에 반영합니다. idle 상태의 일반적인 취소 동작은 유지할 수 있습니다. 공통 내비게이터 전면 변경은 필요하지 않습니다.
- FUP-04: 요청 중에는 본문·별점·스포일러 입력을 같은 상태로 잠급니다. 계속 편집을 허용하려면 제출한 버전과 현재 버전을 구분해 성공 후에도 추가 편집을 보존해야 하지만, 이 짧은 입력 폼에는 전송 중 입력 제한이 더 작은 대응입니다.

## 후속 검증 시나리오

아직 실행하지 않았습니다. 응답을 지연한 독자평 등록·수정 및 토론 답변 등록에서 뒤로 가기, 바깥 탭, 아래로 드래그를 각각 확인합니다. 실패 후 입력은 남고 다시 전송할 수 있어야 하며, 성공으로 닫힐 때 표시했던 최종 입력과 저장된 값이 같아야 합니다.
