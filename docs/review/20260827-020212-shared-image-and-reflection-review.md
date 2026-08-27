# 리뷰 결과

## 요약
- 정적 분석은 통과했지만, 독후감 이미지의 의도치 않은 삭제와 이미지 편집 결과 유실·OCR 해상도 저하, 공개 상태 최신성 문제를 보완해야 한다.

## 문제점
- [문제][높음][이미지 삭제 보호 우회] `_allowTextReplacement()`는 삭제 범위가 이미지를 포함해도 새 데이터가 비어 있지 않은 `String`이거나 `Delta`이면 즉시 허용한다. 따라서 이미지를 포함한 범위를 선택한 뒤 글자를 입력·붙여넣거나, 그 선택 범위에 새 이미지를 삽입하면 이미지가 메뉴의 명시적 삭제 경로를 거치지 않고 사라진다. 사용자가 이 상태로 저장하면 기존 본문 이미지가 영구적으로 빠질 수 있다. (`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:318`, `lib/features/book_reflection/screens/book_reflection_editor_screen.dart:321`, `lib/features/book_reflection/services/book_reflection_memo_insert_service.dart:183`)
- [문제][중간][편집 완료 실패를 취소로 처리] 공용 이미지 에디터는 결과 바이트가 비어 있는지 확인하지 않고 파일로 저장하며, 임시 파일 쓰기 실패는 삼킨 뒤 `null`로 화면을 닫는다. `pro_image_editor`의 캡처 실패는 빈 바이트를 반환할 수 있는데 현재 로컬 저장 검증도 0바이트를 거르지 않아, 빈 JPEG가 메모·독후감에 저장될 수 있다. 파일 쓰기 자체가 실패하면 메모·독후감 호출부는 사용자가 취소한 것으로 간주해 완료한 편집을 조용히 버리고, OCR 호출부는 편집 전 원본을 분석해 크롭·회전이 적용된 것처럼 보인 사용자 기대와 어긋난다. (`lib/shared/image/screens/shared_image_editor_screen.dart:88`, `lib/shared/image/screens/shared_image_editor_screen.dart:98`, `lib/core/storage/local_image_store.dart:146`, `lib/features/book_note/screens/widgets/book_note_memo_sheet.dart:508`, `lib/features/book_reflection/screens/book_reflection_editor_screen.dart:404`, `lib/features/book_note/screens/widgets/memo_ocr_capture.dart:71`)
- [문제][중간][OCR 원본 해상도 손실] OCR 카메라 정책은 인식률을 위해 갤러리 원본을 압축하지 않는다고 명시하지만, 이어서 여는 공용 에디터는 프로필과 무관하게 `ImageGenerationConfigs`의 기본 `maxOutputSize`(2000×2000)를 사용한다. 고해상도 촬영본·갤러리 이미지는 사용자가 크롭/회전 완료를 누르는 순간 최대 2000px로 축소되어 작은 글자의 OCR 인식률이 기존 흐름보다 낮아질 수 있다. (`lib/features/book_note/screens/widgets/memo_ocr_capture.dart:14`, `lib/features/book_note/screens/widgets/memo_ocr_capture.dart:66`, `lib/shared/image/screens/shared_image_editor_screen.dart:61`)
- [문제][중간][공개 상태 갱신 누락] 공개 여부 변경 요청 중에도 바텀시트는 스와이프로 닫을 수 있다. 요청이 성공한 뒤 시트가 이미 닫혔으면 `sheetContext.mounted` 검사에서 반환해 상세 provider 무효화와 동기화 버전 갱신을 모두 건너뛴다. Repository와 서버 값은 바뀌었는데 현재 상세 화면은 이전 `reflection`을 계속 사용하므로, 관리 시트를 다시 열었을 때 스위치가 예전 값을 표시한다. 실패 경로도 시트가 열려 있을 때 값을 되돌릴 뿐 사용자 오류 안내가 없다. (`lib/features/book_reflection/screens/book_reflection_detail_screen.dart:113`, `lib/features/book_reflection/screens/book_reflection_detail_screen.dart:121`, `lib/features/book_reflection/screens/book_reflection_detail_screen.dart:129`, `lib/features/book_reflection/screens/book_reflection_detail_screen.dart:135`)

## 개선 제안
- 이미지 삭제 보호 → `_allowImageDeletion`이 아닌 모든 `length > 0` 교체에서 삭제 범위와 이미지 embed의 겹침을 먼저 검사한다. 입력 데이터가 문자열·embed·Delta인지와 무관하게 이미지를 포함하면 교체를 막고, 이미지 메뉴의 삭제 콜백만 예외로 허용한다.
- 편집 완료 처리 → 빈 바이트와 파일 쓰기 실패를 명시적 실패로 구분하고 공통 Alert로 안내한 뒤 에디터를 유지하거나 재시도할 수 있게 한다. 저장 계층에서도 0바이트 파일을 거부해 손상 파일이 영속 저장소에 들어가는 것을 막는다.
- OCR 이미지 생성 설정 → `cropRotateOnly` 프로필에는 원본 해상도를 보존할 별도 `ImageGenerationConfigs`를 적용하거나 OCR에 충분한 상한을 명시한다. 일반 이미지의 2000px 제한과 OCR 정책을 분리한다.
- 공개 상태 변경 → Repository 성공 후 provider 무효화와 동기화 버전 갱신은 시트 생명주기와 무관하게 항상 실행하고, `setSheetState`만 `mounted`로 보호한다. 실패 시 시트가 닫혀 있어도 상세 화면에서 확인 가능한 오류 안내를 제공한다.
