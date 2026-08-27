# 리뷰 결과

## 요약
- 이전 리뷰의 직접 지적은 반영됐고 정적 분석도 통과했지만, Quill 교체 거부 후 상태 불일치와 공개 설정 완료 시 `WidgetRef` 생명주기 문제 2건이 남아 있다.

## 문제점
- [문제][높음][교체 거부 후 Quill 상태 불일치] 이미지가 포함된 범위의 교체를 `onReplaceText`에서 `false`로 거부하지만, 호출부는 교체 성공 여부를 알지 못한다. `insertImageBlock()`은 `replaceText()`가 거부되어 문서가 바뀌지 않아도 삽입된 길이만큼 선택 위치를 이동하고 `true`를 반환한다. 그 결과 기존 이미지를 포함한 선택 영역에 새 사진이나 사진 메모를 넣으면 새 이미지는 표시되지 않는데 호출부는 성공으로 처리하고, 이미 저장소로 복사한 파일은 참조되지 않은 채 남는다. 키보드 입력 경로에서도 `flutter_quill`은 거부 시 문서·선택 변경과 controller 알림을 모두 생략하므로, 이미 변경값을 보낸 IME와 문서 상태가 다시 동기화되기 전까지 다음 입력 위치·diff가 어긋날 수 있다. (`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:323`, `lib/features/book_reflection/screens/book_reflection_editor_screen.dart:336`, `lib/features/book_reflection/services/book_reflection_memo_insert_service.dart:183`, `lib/features/book_reflection/services/book_reflection_memo_insert_service.dart:187`, `lib/features/book_reflection/services/book_reflection_memo_insert_service.dart:191`)
- [문제][중간][공개 설정 완료 시 dispose된 WidgetRef 사용] 공개 여부 요청 중 시트를 닫은 뒤 상세 화면까지 나가면 네트워크 요청은 계속되지만, 성공 직후 `ref.read()`와 `ref.invalidate()`를 호출할 때 해당 `ConsumerWidget`은 이미 dispose된 상태일 수 있다. Riverpod은 dispose된 `WidgetRef` 사용 시 예외를 던지고, 이 예외는 같은 `catch`에서 저장 실패처럼 삼켜진다. Repository와 서버 값은 이미 변경됐는데 전역 동기화 버전은 증가하지 않아 뒤에 남아 있던 독후감 목록이 오래된 값을 유지할 수 있다. 요청이 실제로 실패한 일반 경로도 시트가 열려 있으면 스위치만 원복되고 오류 안내는 표시되지 않는다. (`lib/features/book_reflection/screens/book_reflection_detail_screen.dart:117`, `lib/features/book_reflection/screens/book_reflection_detail_screen.dart:125`, `lib/features/book_reflection/screens/book_reflection_detail_screen.dart:136`, `lib/features/book_reflection/screens/book_reflection_detail_screen.dart:143`)

## 개선 제안
- Quill 이미지 보호 → 이미지 포함 범위 검사를 공통 함수로 분리해 프로그램 삽입 전에 먼저 실패를 반환하고, 실제 교체가 적용된 경우에만 선택 위치를 이동하고 `true`를 반환한다. 키보드 교체를 거부할 때는 controller 상태를 입력 연결에 다시 게시하거나, `flutter_quill`이 지원하는 입력 이벤트 경계에서 문서·IME 상태가 함께 복원되도록 처리한다.
- 공개 설정 생명주기 → Repository와 전역 동기화 버전 notifier 또는 `ProviderContainer`를 `await` 전에 확보해 화면 dispose 여부와 무관하게 성공 상태를 반영한다. 화면 한정 provider/UI 갱신만 `screenContext.mounted`로 보호하고, 실패 안내는 시트가 열려 있는 경우에도 표시한다.
