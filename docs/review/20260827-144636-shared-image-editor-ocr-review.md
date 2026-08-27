# 리뷰 결과

## 요약
- 정적 분석은 통과했고 이미지 에디터의 도구·색상·문구 구성은 개선됐지만, OCR 전용 크롭의 종료 상태 경합 3건과 단어 선택 접근성 회귀 1건을 보완해야 한다.

## 문제점
- [문제][중간][시스템 뒤로 가기가 크롭 화면을 다시 엶] OCR 크롭 화면에서 Android 시스템 뒤로 가기나 iOS 뒤로 가기 제스처를 사용하면 크롭 서브 라우트가 정상적으로 닫히지만, `_pendingCropExit`이 `null`인 `onEndCloseSubEditor`가 즉시 `openCropRotateEditor()`를 다시 호출한다. 사용자는 이전 OCR 촬영 화면으로 돌아갈 것으로 기대하지만 같은 크롭 화면으로 복귀하며, 시스템 뒤로 가기로는 이 흐름을 종료할 수 없다. (`lib/shared/image/screens/shared_image_editor_screen.dart:129`, `lib/shared/image/screens/shared_image_editor_screen.dart:144`, `lib/shared/image/screens/shared_image_editor_screen.dart:148`)
- [문제][중간][크롭 조작 중 완료 시 종료 버튼이 영구 잠김] `_finishFromOcrCrop()`은 라이브러리가 완료 요청을 수락했는지 확인하기 전에 `_pendingCropExit`을 설정한다. `pro_image_editor` 13.3.1의 `CropRotateEditorState.done()`은 크롭 제스처가 활성화된 동안 호출되면 라우트를 닫지 않고 즉시 반환하므로, 크롭을 누른 상태에서 다른 손가락으로 완료를 누르면 `_pendingCropExit`만 남는다. 이후 완료와 닫기는 모두 `_pendingCropExit != null` 검사에서 무시되어 사용자가 화면에서 나갈 수 없다. (`lib/shared/image/screens/shared_image_editor_screen.dart:388`, `lib/shared/image/screens/shared_image_editor_screen.dart:389`, `lib/shared/image/screens/shared_image_editor_screen.dart:401`, `lib/shared/image/screens/shared_image_editor_screen.dart:402`)
- [문제][중간][OCR 초기화 중 완료와 자동 크롭 진입 경합] 커스텀 메인 상단바는 이미지 디코딩 전에도 완료 버튼을 활성화하지만, OCR 프로필은 같은 시점에 `openCropRotateEditor()`가 디코딩 완료를 기다리고 있다. 고해상도 이미지에서 사용자가 노출된 메인 화면의 완료를 먼저 누르면 디코딩 직후 완료 처리와 크롭 라우트 push가 함께 진행된다. 라이브러리의 최종 캡처가 열린 크롭을 닫을 때 `onEndCloseSubEditor`가 다시 크롭을 열 수 있고, `_finish()`의 `Navigator.pop()`은 메인 에디터가 아니라 새 크롭 라우트를 닫은 뒤 `_hasPopped`를 고정해 호출부의 Future가 끝나지 않을 수 있다. (`lib/shared/image/screens/shared_image_editor_screen.dart:84`, `lib/shared/image/screens/shared_image_editor_screen.dart:89`, `lib/shared/image/screens/shared_image_editor_screen.dart:134`, `lib/shared/image/screens/shared_image_editor_screen.dart:148`, `lib/shared/image/screens/shared_image_editor_screen.dart:491`)
- [문제][중간][스크린 리더용 단어 선택 경로 제거] 기존 체크박스 목록 선택 바텀시트를 제거했지만 이미지 위 단어 영역은 `CustomPaint`와 포인터 제스처로만 구현되어 개별 `Semantics` 노드나 키보드 액션이 없다. 완료 버튼도 단어를 선택하기 전에는 비활성화되므로 스크린 리더·스위치 제어 사용자는 OCR 단어를 하나도 선택할 수 없고 기능을 완료할 수 없다. (`lib/features/book_note/screens/widgets/memo_ocr_capture.dart:176`, `lib/features/book_note/screens/widgets/memo_ocr_capture.dart:194`, `lib/features/book_note/screens/widgets/memo_ocr_capture.dart:311`, `lib/features/book_note/screens/widgets/memo_ocr_capture.dart:343`)

## 개선 제안
- 시스템 뒤로 가기 → 예약 동작 없이 OCR 크롭 서브 라우트가 닫힌 경우에도 전체 편집 취소로 연결하거나, 서브 라우트의 pop을 가로채 `_cancelFromOcrCrop()`과 동일한 종료 상태로 변환한다.
- 크롭 조작 중 완료 → 완료 요청이 실제로 라우트 종료를 시작한 경우에만 `_pendingCropExit`을 유지하고, `done()`이 현재 라우트를 닫지 않고 반환하면 예약 상태를 해제해 재시도할 수 있게 한다.
- OCR 초기 완료 경합 → OCR 프로필의 메인 화면에서는 완료 액션을 숨기거나 비활성화하고, 자동 크롭 서브 화면이 열린 뒤에는 프로그램 방식의 완료 경로만 사용한다.
- OCR 단어 선택 접근성 → 체크박스 기반 목록 선택 경로를 복원하거나 각 인식 단어를 선택 가능한 `Semantics` 노드로 노출해 포인터 없이도 선택·해제할 수 있게 한다.
