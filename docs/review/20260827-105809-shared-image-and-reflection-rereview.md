# 리뷰 결과

## 요약
- 정적 분석은 통과했지만 직전 리뷰 이후 구현 변경이 없어, 이미지 삭제 보호 우회·편집 결과 오류 처리·OCR 해상도·공개 상태 최신성 문제 4건이 모두 남아 있다.

## 문제점
- [문제][높음][이미지 삭제 보호 우회] `_allowTextReplacement()`는 교체 데이터가 비어 있지 않은 문자열이거나 `Delta`이면 삭제 범위 검사를 건너뛴다. 이미지를 포함한 범위를 선택하고 입력·붙여넣기하거나 그 자리에 새 이미지를 삽입하면, 명시적인 이미지 삭제 메뉴를 거치지 않고 기존 이미지가 본문에서 제거된다. (`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:318`, `lib/features/book_reflection/screens/book_reflection_editor_screen.dart:321`, `lib/features/book_reflection/services/book_reflection_memo_insert_service.dart:183`)
- [문제][중간][편집 완료 실패를 취소로 처리] 공용 이미지 에디터는 빈 결과 바이트도 파일로 저장하고, 임시 파일 쓰기 오류는 삼킨 뒤 `null`을 반환한다. 로컬 이미지 저장소도 0바이트를 거르지 않아 손상 이미지가 저장될 수 있으며, 쓰기 실패 시 메모·독후감은 완료한 편집을 취소로 처리하고 OCR은 편집 전 원본을 분석한다. (`lib/shared/image/screens/shared_image_editor_screen.dart:88`, `lib/shared/image/screens/shared_image_editor_screen.dart:98`, `lib/core/storage/local_image_store.dart:146`, `lib/features/book_note/screens/widgets/book_note_memo_sheet.dart:508`, `lib/features/book_reflection/screens/book_reflection_editor_screen.dart:404`, `lib/features/book_note/screens/widgets/memo_ocr_capture.dart:71`)
- [문제][중간][OCR 원본 해상도 손실] OCR 정책은 갤러리 원본을 압축하지 않지만, 이어서 여는 에디터는 모든 프로필에 같은 `ImageGenerationConfigs`를 사용하고 기본 `maxOutputSize` 2000×2000을 그대로 둔다. 고해상도 이미지는 크롭·회전 완료 시 최대 2000px로 축소되어 작은 글자의 인식률이 기존보다 낮아질 수 있다. (`lib/features/book_note/screens/widgets/memo_ocr_capture.dart:14`, `lib/features/book_note/screens/widgets/memo_ocr_capture.dart:66`, `lib/shared/image/screens/shared_image_editor_screen.dart:61`)
- [문제][중간][공개 상태 갱신 누락] 공개 여부 요청 도중 바텀시트를 닫으면, 성공 후 `sheetContext.mounted` 검사에서 반환해 상세 provider 무효화와 동기화 버전 갱신을 생략한다. 서버·DB 값은 바뀌지만 현재 상세 화면은 이전 값을 유지해 관리 시트를 다시 열었을 때 오래된 공개 상태를 표시한다. 실패 역시 사용자에게 안내되지 않는다. (`lib/features/book_reflection/screens/book_reflection_detail_screen.dart:113`, `lib/features/book_reflection/screens/book_reflection_detail_screen.dart:121`, `lib/features/book_reflection/screens/book_reflection_detail_screen.dart:129`, `lib/features/book_reflection/screens/book_reflection_detail_screen.dart:135`)

## 개선 제안
- 이미지 삭제 보호 → 명시적 삭제 플래그가 없는 모든 `length > 0` 교체에서 입력 데이터 타입과 무관하게 이미지 embed 겹침을 검사한다.
- 편집 완료 처리 → 빈 바이트와 파일 쓰기 실패를 오류 결과로 구분하고 공통 Alert로 안내하며, 저장 계층에서도 0바이트 파일을 거부한다.
- OCR 해상도 → `cropRotateOnly` 프로필에 원본 해상도 보존 또는 OCR 전용 상한을 적용해 일반 이미지 출력 설정과 분리한다.
- 공개 상태 → Repository 성공 뒤 provider 무효화와 동기화 버전 갱신은 항상 실행하고, 시트의 `setState`만 `mounted`로 보호한다. 실패 시 화면에서 확인 가능한 오류를 표시한다.
