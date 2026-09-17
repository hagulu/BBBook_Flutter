# 리뷰 결과

## 요약

- 직전 리뷰(`20260917-132747`) 6건 중 3건은 해결, 2건은 부분 해결, 1건은 미해결 상태이며 `flutter analyze`는 통과하지만, 제목 push가 실패한 노트에서 AI 메모를 생성하면 노트 제목이 서버·로컬 모두에서 영구히 사라지는 새 결함 1건을 확인했다.

### 직전 리뷰 항목 처리 현황

| 직전 지적 | 상태 | 근거 |
|---|---|---|
| 미동기화 메모를 빼고 AI 독후감 생성 | 해결 | `ensureNoteSyncedServerId()`가 노트·메모 dirty를 모두 확인한 뒤에만 서버 ID를 반환한다(`book_note_repository.dart:307-314`) |
| 화면 이탈 시 AI 전역 로딩 잔존 | 해결 | 생성 구간을 `_isSavingMemo`로 pop 차단 + `try/finally`에서 `AppAiLoading.hide()` 1회 보장(`book_note_detail_screen.dart:409-441`) |
| AI 제목 255자 초과 | 해결 | 에디터 초기값에서 255자로 절단(`book_reflection_editor_screen.dart:364-369`). 다만 근거로 든 주석이 api-doc과 어긋난다(아래 문제점 참고) |
| AI 메모 실패 후 빈 노트 잔존 | 부분 해결 | `discardIfEmptyAndUnsynced()`가 추가됐지만 실제 삭제 여부와 무관하게 화면 상태를 비운다(아래 문제점 참고) |
| 저장 모드 미확정을 서버 모드로 취급 | 부분 해결 | 화면 조건은 `== StorageMode.server`로 고쳤고 `createAiMemos()`에는 repository 방어가 들어갔지만, `generateAiDraft()`에는 없다 |
| AI 초안 즉시 이탈 시 경고 없이 유실 | 미해결 | AI 초안이 그대로 `_initialTitle`/`_initialDocumentJson` 기준값이 되어 `_hasUnsavedChanges`가 false다 |

## 문제점

- [높음][제목 push 실패 노트에 AI 메모를 만들면 제목이 사라진다] `createAiMemos()`는 `pushNote()`의 성공 여부를 확인하지 않고 그 결과 읽은 `note.serverId`를 그대로 요청에 넣는다(`lib/features/book_note/data/book_note_repository.dart:266-281`). 제목이 있는 신규 노트인데 제목 PUT이 실패하면(`_pushOneNote`는 실패를 로그만 남기고 `return`한다 — `book_note_repository.dart:597-605`) `serverId`는 여전히 null이므로 AI API가 `noteId: null`로 호출되고, 서버는 **제목 없는 새 노트**를 만든다(api-doc `api-me-books-userBookId-notes-memos-ai-post.md`: "노트 제목에는 영향을 주지 않는다"). 그 뒤 `confirmNoteCreated()`가 호출되는데 이 메서드는 제목 PUT 성공 직후에 쓰라고 만든 것이라 `updated_at`이 그대로면 `is_dirty=0`까지 해제한다(`book_note_dao.dart:499-522`). 결과적으로 로컬 제목은 dirty가 풀려 다시는 push되지 않고, 다음 동기화에서 `_upsertServerNoteTxn`이 서버의 `title: null`로 로컬 제목까지 덮어쓴다(`book_note_dao.dart:881-897`). 사용자가 입력한 제목이 조용히 사라진다.
- [중간][AI 독후감 초안이 확인 없이 버려진다] 에디터는 주입받은 AI 제목·본문을 그대로 `_initialTitle`/`_initialDocumentJson` 기준값으로 저장한다(`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:364-383`). 저장 전인데도 `_hasUnsavedChanges`가 false라서(`:558-561`) 뒤로 가기를 누르면 `_handlePopAttempt`가 확인 없이 바로 화면을 닫는다(`:570-587`). 수십 초와 AI 호출 비용을 들여 만든 초안이 경고 한 번 없이 사라지고, 되살리려면 처음부터 다시 생성해야 한다. 직전 리뷰에서 지적했으나 반영되지 않았다.
- [중간][AI 메모 실패 롤백이 실제로 됐는지 확인하지 않는다] 컨트롤러는 이 호출을 위해 노트를 만들었으면 실패 시 `discardIfEmptyAndUnsynced()`를 부른 뒤 무조건 `_noteId = null`, 상태를 `BookNoteDetail.empty()`로 되돌린다(`lib/features/book_note/providers/book_note_providers.dart:243-253`). 그런데 `discardIfEmptyAndUnsynced()`는 `serverId != null`이거나 메모가 남아 있으면 아무 것도 하지 않는다(`book_note_repository.dart:326-332`). `confirmNoteCreated()`까지 성공한 뒤 `upsertServerCreatedMemos()`(로컬 DB 쓰기)에서 실패하면 서버에는 노트와 AI 메모가, 로컬에는 서버 ID가 붙은 노트가 남는데 화면만 "노트 없음"이 된다. 사용자가 이어서 메모를 추가하면 `saveTitle()`이 노트를 하나 더 만들어 같은 책에 중복 노트가 생긴다.
- [낮음][AI 독후감 경로에만 저장 모드 방어가 없다] `createAiMemos()`는 `_storageMode.isLocal()`이면 즉시 거부하지만(`book_note_repository.dart:258-260`) `generateAiDraft()`에는 같은 방어가 없다(`lib/features/book_reflection/data/book_reflection_repository.dart:150-170`). 지금은 화면에서 `storageModeProvider`로 막고 있어 도달할 수 없지만, 직전 리뷰가 요청한 "repository 이중 보장"이 두 진입점 중 하나에만 적용된 상태다.
- [낮음][AI 독후감 생성 중 안내 문구가 사실과 다르다] 생성 중 뒤로 가기를 누르면 `_closeScreen()`이 `_isSavingMemo`를 보고 "메모를 저장하고 있습니다."라고 안내한다(`lib/features/book_note/screens/book_note_detail_screen.dart:307-312`). 실제로는 AI 독후감을 생성 중이라 사용자가 무엇 때문에 막혔는지 알 수 없다. 메모 저장과 AI 생성이 같은 플래그를 공유하면서 생긴 부작용이다.
- [낮음][제목 절단 코드의 근거 주석이 api-doc과 반대다] 주석은 "AI 초안 생성 API는 제목 길이를 검증하지 않는다(api-doc)"라고 적혀 있다(`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:359-363`). 그러나 api-doc `api-me-books-userBookId-notes-noteId-reflections-ai-post.md`는 "title이 255자를 초과하면 … 이 API에서 먼저 AI_RESPONSE_INVALID로 거절한다"(47행)고 명시한다. 절단 코드 자체는 무해하지만, 틀린 전제를 근거로 남겨 두면 이후 이 주석을 믿고 판단하는 코드가 어긋난다.

## 개선 제안

- 제목 push 실패 노트에 그대로 AI 호출 → `serverId == null`인 성공 응답에서는 서버 ID만 연결하고 `is_dirty`는 유지한다(`confirmNoteCreated()` 대신 dirty를 건드리지 않는 전용 경로). 그러면 뒤이은 `unawaited(pushNote(noteId))`가 `note.isDirty` 분기를 타 제목을 새로 연결된 노트에 PUT한다. 더 엄격하게 가려면 `serverId == null && title != null`(= 제목 push가 실패했다는 뜻)일 때 AI 호출 자체를 중단하고 동기화 실패를 안내한다. 다만 "제목 PUT은 서버에 반영됐는데 응답만 유실된" 경우의 노트 중복은 두 방법 어느 쪽으로도 막을 수 없다.
- AI 초안을 저장된 내용처럼 기준값으로 등록 → `reflection == null`이면서 `initialDraftTitle`/`initialDraftContentJson`이 있으면 저장 전까지 `_hasUnsavedChanges`를 true로 본다(예: `_isUnsavedDraft` 플래그를 두고 `_hasUnsavedChanges`에 OR로 더한 뒤 `_save()` 성공 시 해제).
- 롤백 성공을 가정한 상태 초기화 → `discardIfEmptyAndUnsynced()`가 실제 삭제 여부를 `bool`로 반환하게 하고, true일 때만 `_noteId`와 상태를 비운다. false면 노트가 살아 있다는 뜻이므로 `findDetail()`로 다시 읽어 현재 상태를 반영한다.
- AI 독후감 경로의 저장 모드 무방비 → `generateAiDraft()` 진입부에도 `createAiMemos()`와 같은 `_storageMode.isLocal()` 거부를 넣어 두 AI 진입점의 방어 수준을 맞춘다.
- 메모 저장과 AI 생성이 한 플래그를 공유 → `_isSavingMemo`와 별도로 `_isGeneratingAiReflection`(또는 진행 중 작업명 문자열)을 두고 `_closeScreen()`이 실제 진행 중인 작업에 맞는 문구를 보여준다.
- 틀린 전제를 근거로 단 주석 → api-doc 기준으로 "서버가 255자를 초과한 초안을 이미 거절하므로 이 절단은 방어적 안전장치"라고 정정하거나, 서버 검증에 맡기고 절단을 제거한다.
- (선택) 퀵 메모 시트에서 AI 생성이 성공하면 시트를 바로 닫으면서(`book_note_memo_sheet.dart:290-302`) 사용자가 입력 중이던 메모 텍스트가 확인 없이 사라진다. 입력이 남아 있으면 그 내용을 draft로 함께 돌려주거나 닫기 전에 확인을 받는다.

## 문제를 찾지 못한 부분

- `BookNoteDao.upsertServerCreatedMemos()` — `_upsertServerMemoTxn` 재사용으로 dirty 행이 보호되고 `is_dirty=0`으로 들어가 재push되지 않는다. 동봉된 테스트(`test/features/book_note/data/book_note_dao_ai_test.dart`)가 이 두 계약을 모두 덮는다. 메모 정렬도 `created_at ASC` 우선이라(`book_note_dao.dart:110`) AI 메모가 항상 뒤에 붙는다.
- `memo_ocr_capture.dart` 리팩터링 — 이번 AI 기능과 직접 관련은 없지만 함께 확인했다. 분리된 4개 삭제 지점과 호출부 `finally`가 모든 경로를 덮고, `AppLoading.show()` 직전에 `context.mounted` 확인이 있으며(`:97-103`), `_joinWordsAsText()`는 `lineOrder`/`wordOrder`로 다시 정렬하므로 `_selectedIndexes` 사전 정렬을 뺀 것이 결과를 바꾸지 않는다.
- `AppAiLoading` — `AppLoading`과 같은 참조 카운트 방식이고, 두 AI 진입점 모두 `finally`에서 `hide()`를 정확히 한 번 호출한다. `AiGeneratingView`는 `RepaintBoundary`로 감싸고 `MediaQuery.disableAnimationsOf`를 반영한다.
