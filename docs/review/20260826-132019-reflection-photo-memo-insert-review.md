# 리뷰 결과

## 요약
- 정적 분석은 통과했고 사진 메모를 독후감에 삽입하는 기본 흐름은 추가됐지만, 원본과 독립적인 이미지 보존, 비동기 삽입의 생명주기·오류 처리, 기존 단위 테스트의 비동기 계약 반영이 필요하다.

## 문제점
- [문제][높음][독립 사본 미보장] 사진을 로컬 복사하거나 내려받지 못하면 `_resolveReflectionImageSource()`가 원본 메모의 `imageUrl`을 그대로 성공 결과로 반환한다. 이후 독후감 저장 로직은 원격 URL을 이미 업로드된 이미지로 간주해 별도 업로드를 건너뛰므로, 생성된 독후감이 계속 원본 메모 이미지에 의존한다. 특히 `ensureDownloaded()`가 403/404로 `unavailable`을 반환한 경우에도 이미 접근 불가능한 URL을 삽입 성공으로 처리하며, 로컬 저장 모드에서는 `ensureImagesForReflection()`도 즉시 종료되어 나중에 사본을 확보할 기회가 없다. 원본 메모 삭제·URL 만료·오프라인 상황에서 독후감 이미지가 영구적으로 깨질 수 있다. (`lib/features/book_reflection/services/book_reflection_memo_insert_service.dart:168`, `lib/features/book_reflection/services/book_reflection_memo_insert_service.dart:183`, `lib/features/book_reflection/data/book_reflection_repository.dart:456`, `lib/features/book_reflection/data/book_reflection_repository.dart:509`)
- [문제][중간][비동기 삽입 종료 경합] 화면은 서비스 호출 전에만 `mounted`를 확인하지만 서비스는 이미지 복사·다운로드를 기다린 뒤 `QuillController`를 수정한다. 전체 화면 로딩은 `OverlayEntry`의 포인터 장벽이라 시스템 뒤로 가기까지 막지는 않으므로, 대기 중 편집 화면이 닫히면 dispose된 컨트롤러에 `replaceText()`를 호출할 수 있다. 또한 로컬 저장소의 `resolve()`·`exists()` 같은 파일 I/O 예외가 서비스 밖으로 전달돼도 호출부는 `try/finally`만 사용하므로 사용자 안내 없이 처리되지 않은 비동기 오류가 된다. (`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:396`, `lib/features/book_reflection/screens/book_reflection_editor_screen.dart:400`, `lib/features/book_reflection/services/book_reflection_memo_insert_service.dart:98`, `lib/features/book_reflection/services/book_reflection_memo_insert_service.dart:174`)
- [문제][중간][기존 테스트 실패] `BookReflectionMemoInsertService.insert()`의 반환형이 `bool`에서 `Future<bool>`로 바뀌었지만 기존 테스트는 비동기 함수로 전환하지 않고 반환값 자체를 `isTrue`와 비교한다. 따라서 첫 테스트는 실제 삽입 결과가 `true`여도 `Future<bool>` 객체를 비교해 실패하며, 새 사진 분기의 복사·다운로드 실패 동작도 검증되지 않는다. (`lib/features/book_reflection/services/book_reflection_memo_insert_service.dart:16`, `test/features/book_reflection/services/book_reflection_memo_insert_service_test.dart:10`, `test/features/book_reflection/services/book_reflection_memo_insert_service_test.dart:20`)

## 개선 제안
- 원본 메모 URL 폴백 → 독후감 이미지 저장소에 실제 사본이 만들어진 경우에만 삽입을 성공시키고, 복사·다운로드 실패 시 `false`를 반환해 저장되지 않게 한다. 일시 실패를 허용해야 한다면 원본 URL을 그대로 저장하지 말고 독후감 전용 재시도 상태와 로컬 사본 확보 완료 여부를 추적한다.
- 비동기 이미지 확보와 화면 생명주기 → 파일 확보와 컨트롤러 변경 단계를 분리해 `await` 직후 화면의 `mounted`를 다시 확인한 뒤 문서를 수정하거나, 작업 중 뒤로 가기를 명시적으로 차단한다. 파일 I/O 예외는 호출 경계에서 일관된 로그와 오류 스낵바로 변환한다.
- 변경된 비동기 계약 → 관련 테스트 콜백을 `async`로 바꾸고 `await service.insert(...)` 결과를 검증한다. 주입 가능한 이미지 저장소를 사용해 로컬 사본 복사, 원격 다운로드 성공, `failed`·`unavailable`, 대기 중 취소 경로를 각각 테스트한다.
