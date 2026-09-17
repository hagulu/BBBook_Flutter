# 리뷰 결과

## 요약

- AI 메모·독후감 생성 변경은 `flutter analyze`를 통과했지만, 실패 시 빈 노트 잔존·미동기화 메모 누락·전역 로딩 잔존 등 사용자 데이터와 화면 진행을 해칠 수 있는 문제 6건을 확인했다.

## 문제점

- [높음][AI 메모 실패 후 빈 노트 잔존] 신규 노트에서 AI 메모 생성을 시작하면 API 요청 전에 `saveTitle(null)`로 로컬 노트를 먼저 만든다(`lib/features/book_note/providers/book_note_providers.dart:229-240`). 이후 네트워크 오류, AI Provider 오류, 응답 파싱 오류가 나면 생성한 노트를 되돌리는 경로가 없고 notifier 상태에도 빈 노트가 남는다. 노트 목록 조회는 메모 0개인 노트도 포함하므로, 사용자가 생성 화면을 취소하고 나가면 제목 없는 `메모 0개` 노트가 실제 기록처럼 노출된다. 일반 메모 생성은 로컬 메모까지 바로 저장하는 흐름이지만 AI 메모는 네트워크가 선행되므로 같은 전제를 적용할 수 없다.
- [높음][미동기화 메모를 빼고 AI 독후감 생성] `ensureNoteSyncedServerId()`는 `pushNote()`를 기다린 뒤 서버 노트 ID가 있는지만 확인한다(`lib/features/book_note/data/book_note_repository.dart:297-304`). 그러나 `pushNote()`는 제목·메모별 push 실패를 로그로만 남기고 정상 완료하므로, 수정/추가한 dirty 메모가 서버에 반영되지 않아도 기존 `serverId`를 반환한다. 그 상태로 AI API를 호출하면 화면에는 보이는 최신 메모가 빠지거나 과거 내용으로 독후감이 생성될 수 있다.
- [높음][화면 이탈 시 AI 전역 로딩 잔존] AI 독후감 생성 중 시스템 뒤로 가기를 누르면 노트 화면의 `PopScope`가 화면을 닫을 수 있다. 가장 오래 걸리는 `generateAiDraft()` 대기 중 화면이 dispose된 뒤 응답이 오면 `if (!mounted) return`이 먼저 실행되어 `AppAiLoading.hide()`가 호출되지 않는다(`lib/features/book_note/screens/book_note_detail_screen.dart:404-427`). `AppAiLoading`은 정적 `OverlayEntry`와 ref count를 사용하므로 오버레이가 다음 화면에도 남아 앱 조작을 계속 차단할 수 있다.
- [중간][AI 초안 즉시 이탈 시 경고 없이 유실] 에디터는 전달받은 AI 제목·본문을 컨트롤러에 넣은 직후 그 값을 `_initialTitle`/`_initialDocumentJson` 기준값으로 저장한다(`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:355-375`). 따라서 생성된 초안이 아직 한 번도 저장되지 않았어도 `_hasUnsavedChanges`가 false이고, 뒤로 가면 저장 확인 없이 바로 닫혀 방금 생성한 결과가 사라진다(`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:550-566`).
- [중간][저장 모드 미확정 상태를 서버 모드로 취급] AI 노출 조건이 `storageModeProvider.valueOrNull != StorageMode.local`이라 provider가 loading/error여서 값이 null인 동안에도 true가 된다(`lib/features/book_note/screens/book_note_detail_screen.dart:91-93`, `356-365`). 생성 repository에도 로컬 모드 방어가 없어, 로컬 저장 사용자가 이 짧은 구간이나 provider 오류 상태에서 진입하면 서버 전용 AI API와 기록 push가 실행될 수 있다.
- [중간][AI 제목 255자 초과를 저장 전에 차단하지 않음] AI 독후감 API 문서는 생성 초안에서 제목 길이를 검증하지 않으며, 실제 독후감 생성 API는 255자를 초과하면 400을 반환한다. 에디터의 `maxLength: 255`는 사용자가 입력하는 변경에는 적용되지만 컨트롤러에 주입된 초기 문자열을 잘라내지 않고, `_save()`도 빈 제목만 검사한다(`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:419-446`, `672-675`). 긴 AI 제목은 로컬에는 저장된 뒤 백그라운드 push만 계속 실패해 서버와 영구적으로 어긋날 수 있다.

## 개선 제안

- API 전 로컬 빈 노트 생성 → 신규 AI 요청에는 `noteId: null`을 보내 성공 응답을 받은 뒤 로컬 노트와 메모를 한 트랜잭션으로 만들고 서버 ID를 연결한다. 기존 구조를 유지한다면 이 호출에서 새로 만든 노트인지 추적해 실패 시 제목·메모·서버 ID가 모두 없는 경우에만 안전하게 정리한다.
- 서버 노트 ID 확인만 수행 → AI 독후감 전용 동기화 결과를 반환하고, 대상 노트나 메모에 dirty 행이 하나라도 남으면 AI 호출을 중단해 동기화 실패를 안내한다. `pushNote()`의 기존 조용한 실패 계약은 다른 호출부를 위해 유지하되 전용 검증을 추가한다.
- 성공/예외 분기에서 개별 `hide()` 호출 → 초안 생성 대기 구간을 `try/finally`로 감싸 `AppAiLoading.hide()`가 정확히 한 번 실행되게 하고, 생성 중에는 노트 화면의 pop도 막거나 명시적으로 취소 처리한다.
- AI 초안을 기존 문서의 초기 기준으로 등록 → `reflection == null`이면서 초기 초안이 있으면 저장 전까지는 변경 사항이 있는 것으로 간주해 이탈 확인을 띄운다.
- `null != local` 조건 및 화면 전용 차단 → AI 기능은 저장 모드가 명시적으로 `StorageMode.server`일 때만 노출하고, repository에서도 `StorageMode.local`이면 요청을 거부해 데이터 정책을 이중으로 보장한다.
- 입력 위젯의 `maxLength`에만 의존 → AI 초안을 에디터에 넣을 때 또는 저장 직전에 제목 길이를 검증해 사용자가 수정하도록 안내하고, 255자 이하일 때만 로컬 저장을 허용한다.

