# 리뷰 결과

대상: 독후감 리치 텍스트 에디터(flutter_quill) 도입 + 로컬 우선 작성/수정/삭제 push 경로 추가

## 요약
- 로컬 우선 저장 + dirty push 구조와 Delta/Tiptap 어댑터 경계는 노트 기능 패턴을 잘 따랐고 `flutter analyze`도 깨끗하지만, push 4xx 영구 재시도·이미지 형식 미변환·미저장 이탈 보호 부재 등 사용자 데이터와 직결된 문제가 남아 있다.

## 문제점

- [문제] `book_reflection_repository.dart:_pushOne`의 생성/수정 경로에 종료 조건이 없다. 삭제는 404를 "이미 삭제됨"으로 확정 처리(`confirmDelete`)하는데, `_api.create`/`_api.update`는 400·404를 받아도 로그만 남기고 `is_dirty=1`을 유지한다. PATCH 404는 문서상 "독후감 없음/숨김/타인 소유"(`api-reflections-reflectionId-patch.md`)라 재시도해도 절대 성공하지 않고, POST 400(contentText 누락 등)/404(userBookId 없음)도 마찬가지다. 이 행은 매 `sync()`마다 같은 요청을 영원히 반복한다. 같은 실패 모드를 `book_note_repository.dart:778` 주석이 이미 "push가 영원히 400으로 실패하는 메모가 남는다"라고 명시하고 노트 쪽은 사전 검증으로 막아 두었는데, 새 코드는 `_reasonOf`로 400/404를 분류만 하고 아무 분기도 하지 않는다.

- [문제] 위 문제 때문에 `sync()` 첫 단계인 `pushAllDirty()`가 dirty 행을 직렬로 순회하므로, 실패가 고정된 행 하나가 당겨서 새로고침마다 왕복 1회씩 비용을 추가한다.

- [문제] `book_reflection_editor_screen.dart:319`의 `ImagePicker().pickImage(source: ImageSource.gallery)`에 재인코딩 옵션이 없다. `book_reflection_repository.dart:uploadImage`는 jpg/jpeg/png/webp·5MB만 통과시키는데, iOS 갤러리 기본 포맷은 HEIC이고 고해상도 원본은 5MB를 쉽게 넘는다. 같은 프로젝트의 `memo_photo_camera_screen.dart:293`은 정확히 이 이유로 `imageQuality: 85, maxWidth: 1600`을 지정하고 주석까지 남겨 두었다. 현재 구현은 아이폰 사용자의 상당수 사진이 "JPEG, PNG, WEBP 이미지만 첨부할 수 있습니다."로 거절된다.

- [문제] 에디터에 미저장 이탈 보호가 없다. `BookReflectionEditorScreen`은 `PopScope`가 없어 AppBar 뒤로가기나 Android 뒤로가기 제스처로 본문 전체가 아무 확인 없이 사라진다. `book_note_detail_screen.dart:88`에는 이미 `PopScope`/`canPop` 패턴이 있어 프로젝트 선례도 있다.

- [문제] `book_reflection_editor_screen.dart`가 1127줄이고 화면 외의 것을 다 담고 있다. `bookReflectionQuillStyles`, `reflectionTextSpanBuilder`, `ReflectionQuillEditor`를 `book_reflection_detail_screen.dart`가 이 화면 파일에서 import하고 있어 screen이 screen에 의존한다. `ReflectionQuillEditor._firstQuoteLineOffsets`는 Delta를 직접 파싱하는 로직인데 위젯 State 안에 있다. CLAUDE.md의 "screen은 얇게 유지하고 로직은 model/service로 분리"에 어긋난다. (`reflection_memo_picker_sheet.dart:9`가 `book_note_detail_screen.dart`의 `BookNoteMemoTimelineItem`을 import하는 것도 같은 형태다.)

- [문제] `ReflectionQuillEditor`가 스크롤 프레임마다 에디터 전체를 rebuild한다. `initState`에서 `scrollController.addListener(_scheduleQuoteUpdate)`를 걸고, 콜백이 post-frame에서 좌표를 다시 계산해 `setState`를 호출한다. 스크롤 중에는 인용 마크 좌표가 매 프레임 바뀌므로 `_sameOffsets` 조기 반환이 걸리지 않고, `build()`가 `Stack` + `QuillEditor`를 통째로 다시 만든다. 긴 본문일수록 스크롤이 무거워진다.

- [문제] `docs/file-index.md`에 신규 6개 파일이 누락됐다. `screens/widgets/reflection_image_embed_builder.dart`, `screens/widgets/reflection_memo_picker_sheet.dart`, `screens/widgets/reflection_title_body_divider.dart`, `services/book_reflection_content_adapter.dart`, `services/book_reflection_memo_insert_service.dart`, `services/book_reflection_quote_service.dart`. 인덱스는 다른 기능의 `screens/widgets/`·`services/` 파일을 모두 싣고 있어 관례상 대상이 맞다.

- [문제] `_EditorColorButton`의 색상 선택이 스크린 리더·키보드로 접근 불가능하다. `PopupMenuItem(enabled: false)` 안에 swatch들을 넣어 두어 메뉴 항목 자체가 선택 대상에서 빠지고, 실제 선택은 내부 `InkResponse`의 raw 탭에만 반응한다.

## 개선 제안

- push 4xx 영구 재시도 → `_pushOne`의 create/update `catch`에서 `ApiException.statusCode`가 400/404일 때 삭제 경로와 같이 종료 처리한다. 404(update)는 서버에 없는 행이므로 로컬 행을 제거하거나 `is_dirty=0`으로 내려 재시도를 끊고, 400은 재시도해도 통과하지 못하므로 dirty를 해제한 뒤 사용자에게 알릴 수 있는 상태를 남긴다(최소한 `_reasonOf` 분류를 실제 분기에 연결). 함께, `_save` 시점에 `contentText`가 비어 있는 저장을 막아 400 자체를 줄인다.

- HEIC/용량 거절 → `_pickAndUploadImage`의 `pickImage`에 `imageQuality: 85, maxWidth: 1600`을 지정해 `memo_photo_camera_screen.dart`와 동일하게 JPEG 재인코딩되도록 한다. 확장자 판정도 `filePath.split('.').last` 대신 `path.extension(filePath).toLowerCase()`를 쓰면 점 없는 경로나 `.JPG` 같은 입력에서 더 안전하다.

- 미저장 이탈 → 에디터를 `PopScope`로 감싸고, 제목/문서가 초기 상태와 달라졌을 때만 `AppConfirm.show()`로 "저장하지 않고 나갈까요?"를 확인한다.

- 화면 비대 → `bookReflectionQuillStyles`/`reflectionTextSpanBuilder`/`ReflectionQuillEditor`를 `screens/widgets/reflection_quill_editor.dart`로 옮겨 상세·에디터가 함께 참조하게 하고, 툴바와 버튼들은 `screens/widgets/reflection_editor_toolbar.dart`로 분리한다. `_firstQuoteLineOffsets`의 Delta 파싱은 이미 있고 테스트도 있는 `BookReflectionQuoteService`로 옮긴다. `BookNoteMemoTimelineItem`도 `book_note/screens/widgets/`로 내려 screen 간 import를 없앤다.

- 스크롤 rebuild → `_quoteOffsets`를 `ValueNotifier<List<Offset>>`로 바꾸고 `build()`에서 `ValueListenableBuilder`로 오버레이(`Positioned` 목록)만 감싼다. `QuillEditor` 서브트리는 스크롤 중 재생성되지 않는다.

- file-index 누락 → `file-index` 스킬 기준으로 `## features/book_reflection` 섹션에 신규 6개 파일 항목을 추가한다.

- 색상 선택 접근성 → `PopupMenuButton` + `enabled: false` 조합 대신 각 색상을 개별 `PopupMenuItem<String>`으로 만들거나(가로 배치가 필요하면) `showModalBottomSheet` + `RecordDialogShell`로 바꿔 항목 하나하나가 접근성 트리에 노출되게 한다.

- 공개 전환만 온라인 전용 → `setPublic`은 API 성공 후 로컬을 갱신하는 유일한 API-first 경로라, 같은 화면의 수정/삭제가 오프라인에서 동작하는 것과 달리 오프라인이면 실패한다. `updateVisibilityLocal`에서 `is_dirty=1`을 세우고 `pushReflection`에 맡기면 나머지 경로와 일관된다. 지금 구조에서는 API가 성공한 뒤 로컬 update가 `count != 1`로 `StateError`를 던지면 서버·로컬이 갈라지는 창도 있다.

- 본문 이미지의 오프라인/만료 → 노트는 사진을 앱 디렉터리에 복사해 두고 push 시점에 업로드하는데, 독후감은 삽입 즉시 `/api/reflections/images/temp`로 올린다. 오프라인에서 이미지 첨부가 불가능하고, push가 오래 지연되면 임시 경로 이미지가 정리되어 본문 이미지가 깨질 여지도 있다. 노트와 같은 "로컬 보관 → push 시 업로드" 방식을 검토할 만하다.

- build 부작용 → `_editorBodyWidth`를 `LayoutBuilder`의 `builder` 안에서 대입하고 있다. `_insertImage`에서 필요한 값이므로 `GlobalKey`로 본문 영역의 `RenderBox` 폭을 읽거나, 이미지 삽입 콜백을 `LayoutBuilder` 안쪽에서 `constraints`를 클로저로 잡아 만들어 넘기는 편이 안전하다.

- 인용 오버레이 스크린 리더 → `Positioned` 안의 `Text('“')`는 장식이므로 `ExcludeSemantics`로 감싼다. 현재는 본문 낭독 중 따옴표 문자가 그대로 읽힌다.
