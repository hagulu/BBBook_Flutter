# 리뷰 결과

## 요약

- 카테고리 모델·API·provider를 책장 계층으로 모으고 SQLite v2 캐시와 조건부 구독을 추가해 직전 리뷰의 기능 역참조와 화면별 반복 조회 문제는 해소됐다.
- 다만 로그인 갱신 결과가 `keepAlive`된 provider에 반영되지 않는 캐시 정합성 문제와 빈 서버 목록 처리 문제가 새로 남아 있으며, 책 정보 수정 다이얼로그의 상태·접근성·반응형 문제도 아직 유지된다.
- 검증: API 문서와 요청·응답 규격을 대조했고 `flutter analyze`는 `No issues found`로 통과했다. 프로젝트 지침에 따라 앱 실행과 테스트는 수행하지 않았다.

## 문제점

- [문제][높음][캐시/상태 정합성] `lib/features/auth/providers/auth_notifier.dart:64`~`:69`, `:89`~`:95`는 인증 상태를 먼저 노출한 뒤 카테고리 갱신을 백그라운드에서 실행하고, `:179`~`:184`는 DB만 갱신한다. 반면 `lib/features/bookshelf/providers/bookshelf_providers.dart:26`~`:33`의 provider는 최초 성공 값을 `keepAlive`한 뒤 무효화되지 않는다. 기존 캐시가 있는 상태에서 화면이 먼저 열리거나 같은 앱 프로세스에서 로그아웃 후 재로그인하면 UI는 이전 `AsyncData`를 계속 사용하고, 뒤늦게 DB가 최신 목록으로 교체돼도 현재 세션의 카테고리 이름·색상·선택지는 갱신되지 않는다.
- [문제][중간][캐시 삭제 정합성] `lib/features/bookshelf/data/bookshelf_repository.dart:130`~`:135`는 서버가 빈 카테고리 배열을 정상 반환하면 `replaceAll`을 호출하지 않는다. API는 활성 카테고리 목록을 반환하므로 모든 카테고리가 비활성화된 경우 빈 배열이 유효한 최신 상태인데, 기존 DB 행은 그대로 남아 삭제·비활성화된 카테고리가 계속 표시된다. `BookCategoryDao.replaceAll`은 트랜잭션으로 기존 목록을 안전하게 교체하므로 성공한 빈 응답도 캐시에 반영해야 한다.
- [문제][중간][상태/오류 처리] `lib/features/book_record/screens/widgets/book_info_edit_dialog.dart:220`~`:250`은 `categoriesAsync.valueOrNull`만 사용해 로딩과 오류를 모두 `categories == null`로 합친다. 최초 설치·오프라인처럼 로컬 캐시도 없고 API도 실패한 경우, 기존 책에 카테고리가 있어도 필드는 `미지정`으로 표시되고 비활성화되며 오류 안내나 재시도 수단이 없다. 내부 `_selectedCategoryId`는 유지되므로 화면 표시와 저장 시 전송 값도 달라진다.
- [문제][중간][접근성] `lib/features/book_record/screens/widgets/book_info_edit_dialog.dart:291`~`:308`은 기존 `InputDecoration.labelText`를 별도의 `Text` 위젯으로 옮기고 실제 `TextField`에는 접근성 이름을 남기지 않았다. 스크린 리더가 편집 컨트롤만 순회하면 제목·저자·출판사·총 쪽수 입력창을 서로 구분할 수 없다.
- [문제][중간][렌더링/텍스트 배율] `lib/features/book_record/screens/widgets/book_info_edit_dialog.dart:321`~`:365`은 92dp 표지, 32dp 간격, 고정 패딩과 텍스트를 가진 작업 버튼 열을 모두 비유연한 `Row`에 배치한다. 기본 `Dialog`의 inset과 내부 24dp 패딩을 적용하면 320dp 화면의 콘텐츠 폭은 약 192dp라 이 행의 최소 폭보다 좁고, 더 넓은 화면에서도 텍스트 배율을 높이면 수평 overflow가 발생할 수 있다.

## 개선 제안

- 로그인 갱신이 DB만 교체하고 provider 상태는 유지함 → `refreshCategories()` 성공 후 `bookCategoriesProvider`를 무효화해 현재 구독자가 새 DB 값을 다시 읽게 하거나, 갱신 메서드가 DB와 provider 상태를 함께 갱신하는 단일 카테고리 컨트롤러로 관리한다. 캐시가 없는 초기 진입에서 prefetch와 provider가 동시에 GET을 시작하지 않도록 진행 중인 갱신 Future도 공유한다.
- 빈 서버 목록을 캐시에 반영하지 않음 → API 호출 자체가 성공했다면 목록 길이와 관계없이 `replaceAll(categories)`를 실행해 기존 행을 제거한다. 빈 목록도 유효한 캐시로 구분해야 한다면 별도의 마지막 갱신 메타데이터를 저장한다.
- 카테고리 로딩·오류·값 없음이 모두 `미지정`으로 표시됨 → `AsyncValue`의 loading/error/data를 구분해 로딩 표시와 오류·재시도 UI를 제공하고, 로딩 중에는 `widget.book.category`를 사용해 현재 선택을 정확히 보여준다.
- 시각적 라벨과 입력 컨트롤의 접근성 이름이 분리됨 → 외부 라벨 디자인은 유지하되 각 `TextField`에 해당 라벨을 포함한 `Semantics`를 연결하거나 시맨틱에 남는 `labelText` 구조를 사용한다.
- 고정 폭 요소를 한 행에 배치함 → 가용 폭과 텍스트 배율에 따라 `Wrap`/세로 배치로 전환하거나 작업 버튼 영역을 `Flexible`로 만들어 좁은 화면에서도 수평 overflow가 발생하지 않게 한다.
