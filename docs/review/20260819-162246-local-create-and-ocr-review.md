# 리뷰 결과

## 요약
- 로컬 CREATE 멱등 키와 메모의 로컬/서버 ID 분리는 전반적으로 잘 반영됐지만, 책 생성 직후의 상태 경합과 영구 실패 처리, 카메라 생명주기에 출시 전 수정이 필요한 문제가 있다.

## 문제점
- [높음][데이터 정합성] 로컬 책 CREATE가 진행 중일 때 태그를 추가하거나 삭제하면 서버 ID와 서버 확정 데이터를 다시 로컬 임시 값으로 덮을 수 있다. `BookRecordRepository.addTag`/`removeTag`는 CREATE 전의 `current`를 먼저 읽고, `_requireServerId`에서 CREATE 완료를 기다린 뒤에도 그 오래된 객체로 `copyWithTags`를 만든다(`lib/features/book_record/data/book_record_repository.dart:199`, `lib/features/book_record/data/book_record_repository.dart:214`, `lib/features/book_record/data/book_record_repository.dart:255`). 이 객체의 `serverId`는 여전히 null이므로 `BookshelfDao._upsertItemTxn`은 음수 `userBookId`를 `incomingServerId`로 사용해 방금 확정된 실제 `server_id`와 제목·표지 등을 덮어쓴다(`lib/features/bookshelf/data/bookshelf_dao.dart:516`, `lib/features/bookshelf/data/bookshelf_dao.dart:550`). 이후 PATCH는 음수 서버 ID로 전송되어 계속 실패할 수 있다.
- [높음][오류 처리] ISBN/커스텀 책 CREATE의 첫 서버 요청이 400·404·409·500·502처럼 재시도로 해결되지 않는 오류여도 화면은 등록 성공으로 처리한다. `createIsbnBook`과 `createCustomBook`은 로컬 행만 만든 뒤 push를 기다리지 않고 반환하고(`lib/features/bookshelf/data/bookshelf_repository.dart:372`, `lib/features/bookshelf/data/bookshelf_repository.dart:429`), push는 모든 `ApiException`을 로그로만 남겨 호출부에 전달하지 않는다(`lib/features/bookshelf/data/bookshelf_repository.dart:243`). 따라서 바코드가 서버에 없는 ISBN이거나 서버에 이미 존재하는 ISBN이어도 성공 스낵바가 뜨고 영구 dirty 행이 남는다(`lib/features/book_search/screens/barcode_scan_screen.dart:125`). 이 행의 삭제도 먼저 CREATE 성공을 요구하므로(`lib/features/book_record/data/book_record_repository.dart:234`) 사용자가 앱에서 정리하기 어렵다.
- [중간][기능 정합성] 동일 ISBN이 로컬에 있으면 요청한 상태와 완독 메타데이터를 모두 무시하고 기존 행을 그대로 성공 반환한다(`lib/features/bookshelf/data/bookshelf_repository.dart:342`). 바코드 빠른 등록은 반환된 책의 실제 상태를 확인하지 않고 사용자가 방금 고른 상태로 “등록완료”를 표시하므로(`lib/features/book_search/screens/barcode_scan_screen.dart:122`, `lib/features/book_search/screens/barcode_scan_screen.dart:136`), 예를 들어 이미 `READING`인 책을 `FINISHED`로 등록했다고 잘못 안내할 수 있다.
- [중간][상태 최신성] CREATE 성공 후 `confirmCreate`가 서버 제목·표지 URL·실제 ID를 DB에 기록해도 목록 provider를 다시 읽게 하는 신호가 없다(`lib/features/bookshelf/data/bookshelf_repository.dart:301`). 화면은 background push가 끝나기 전에 `bookshelfSyncVersionProvider`를 한 번만 올린다(`lib/features/book_search/screens/barcode_scan_screen.dart:132`, `lib/features/book_search/screens/widgets/custom_book_dialog.dart:160`). 그 결과 바코드 등록 책은 `ISBN 978...` 자리표시 제목으로, 직접 등록한 책은 선택한 표지 없이 보인 뒤 다음 동기화까지 갱신되지 않을 수 있다.
- [중간][생명주기] OCR 카메라 화면은 `initState`에서 컨트롤러를 만들고 `dispose`에서만 해제하며 앱 생명주기 전환을 처리하지 않는다(`lib/features/book_memo/screens/memo_ocr_camera_screen.dart:30`, `lib/features/book_memo/screens/memo_ocr_camera_screen.dart:36`). 사용 중인 `camera` 패키지는 앱이 inactive/paused가 될 때 카메라 리소스를 호출부가 직접 해제하고 resumed에서 다시 초기화하도록 요구하므로, 권한 화면·앱 전환·백그라운드 복귀 후 검은 미리보기나 카메라 점유 오류가 발생할 수 있다.
- [중간][접근성] OCR 결과의 단어 선택은 사진 위 `GestureDetector` 드래그와 `CustomPaint` 표시로만 제공된다(`lib/features/book_memo/screens/widgets/memo_ocr_capture.dart:252`). 인식된 단어에 `Semantics`나 키보드/스크린 리더로 조작 가능한 대체 목록이 없어 시각 보조 기술 사용자는 발췌문을 선택할 수 없다.

## 개선 제안
- 태그 직후 서버 ID 손상 → `_requireServerId`가 ID만 반환하지 말고 CREATE 완료 후 다시 읽은 최신 `BookItem`을 반환하게 하거나, `addTag`/`removeTag`가 서버 ID 확정 뒤 로컬 행을 재조회한 객체에 태그를 병합한다. DAO에서도 음수 로컬 ID를 `server_id` 대체값으로 쓰지 않도록 방어한다.
- 영구 CREATE 오류의 가짜 성공·고립 행 → 첫 push 결과를 `localSaved/serverConfirmed/retryableFailure/permanentFailure`처럼 호출부가 구분할 수 있게 반환하고, 네트워크·5xx만 dirty 재시도 대상으로 유지한다. 400·404·409 같은 영구 오류는 사용자에게 안내한 뒤 로컬 임시 행과 관리 표지를 정리하거나 사용자가 “로컬 등록 취소”로 삭제할 수 있게 한다.
- 기존 ISBN의 상태 무시 → 기존 행을 반환할 때는 별도 `alreadyExists` 결과를 사용해 409와 같은 안내를 표시하고, 요청 상태로 바꾸려는 의도가 있다면 명시적인 기록 수정 흐름으로 분리한다.
- CREATE 확정 데이터 미갱신 → `confirmCreate`로 실제 DB 변경이 끝난 시점에 `bookshelfSyncVersionProvider`를 올리거나, push 완료 Future를 await한 뒤 목록을 무효화한다. 오프라인이면 로컬 저장 신호만 즉시 보내고 서버 확정 신호는 나중에 별도로 보낸다.
- 카메라 복귀 오류 → 화면 State에 `WidgetsBindingObserver`를 적용해 inactive/paused에서 컨트롤러를 dispose하고 resumed에서 안전하게 재초기화한다. 중복 초기화도 단일 Future 또는 상태 플래그로 직렬화한다.
- OCR 선택 접근성 → 인식된 문장/단어를 순서대로 보여주는 체크 가능한 텍스트 목록을 사진 선택 방식과 함께 제공하고, 선택 개수와 완료 상태를 `Semantics`로 알린다.
