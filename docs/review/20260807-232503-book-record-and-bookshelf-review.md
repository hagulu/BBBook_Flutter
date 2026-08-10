# 리뷰 결과

## 요약
- 책 기록의 서버 우선 저장·로컬 반영 구조와 책장 목록 갱신 방향은 적절하지만, 상세 상태 캐시의 최신성, 저장/삭제 경합, 포팅 기능 누락 때문에 현재 변경을 그대로 완료 상태로 보기 어렵다.

## 문제점
- [높음][상태 최신성·계정 격리] `lib/features/book_record/providers/book_record_providers.dart:31`은 `bookshelfSyncVersionProvider`를 구독하지 않고, `:124`의 family provider도 `autoDispose`가 아니다. 따라서 상세 화면을 닫은 뒤 다른 기기 변경을 동기화해도 같은 책에 재진입하면 기존 `BookItem` 캐시가 그대로 재사용된다. 로그아웃 시에도 `lib/features/auth/providers/auth_notifier.dart:152`가 이 family provider를 무효화하지 않아 이전 계정의 상세 데이터가 메모리에 남는다. 화면이 열린 동안 백그라운드 동기화로 책이 수정·삭제된 경우에도 상세 화면은 갱신되지 않는다.
- [높음][동시 수정·삭제 경합] `lib/features/book_record/providers/book_record_providers.dart:112`는 수정 중 상태를 이전 값이 포함된 loading으로 만들고, `lib/features/book_record/screens/book_record_screen.dart:58`은 `valueOrNull`만 확인해 AppBar 삭제 버튼을 계속 활성화한다. 이때 PATCH와 DELETE를 함께 실행할 수 있다. PATCH가 서버에서 먼저 처리됐지만 응답이 늦게 도착하면 DELETE가 로컬 행을 지운 뒤 `lib/features/book_record/data/book_record_repository.dart:123`의 `_persist`가 그 행을 다시 upsert하여, 서버에서는 삭제된 책이 로컬 책장에 되살아날 수 있다.
- [높음][포팅 범위 누락] `docs/porting-reference/features/book-record.md:6`과 `:16`~`:20`은 정보·메모·독후감·커뮤니티·토론·공개 독후감 탭, ISBN 연결, 관련 API 흐름을 책 기록 기능으로 정의한다. 그러나 `lib/features/book_record/screens/book_record_screen.dart:147`~`:223`은 정보 일부만 단일 스크롤 화면으로 제공하고, 라우터에도 `/records/:id` 진입점이 없다. 메모/독후감/커뮤니티 계열 탭과 ISBN 연결뿐 아니라 독서 기간·유입 경로·평가/한줄평 재편집 흐름도 접근할 수 없다.
- [중간][완독 데이터 불일치] `lib/features/book_record/screens/book_record_screen.dart:274`~`:282`는 상태만 `FINISHED`로 바꾸고 `totalPages`가 있는 책의 `currentPage`를 마지막 쪽으로 맞추지 않는다. 기준 프런트는 완독 처리 시 `currentPage = totalPages`를 함께 저장하므로, 현재 구현에서는 300쪽 책을 30쪽 상태로 완독 처리하는 식의 모순된 데이터가 남는다.
- [중간][플랫폼 선택 상태] `lib/features/book_record/screens/widgets/meta_dialogs.dart:51`~`:56`은 서버 옵션 목록에 없는 기존 직접 입력 플랫폼을 선택 상태로 복원하지 않아 입력칸을 숨긴다. 또한 플랫폼을 '미설정'으로 바꾸는 선택지가 없고, `:85`~`:92`의 null 결과는 `lib/features/book_record/data/book_record_api.dart:60`에서 요청 본문에서 빠지므로 기존 플랫폼을 지울 수 없다. API 문서상 빈 문자열을 보내야 null로 저장된다.
- [중간][비동기 생명주기·이미지 유효성] `lib/features/book_record/screens/widgets/tag_section.dart:60`~`:68`은 await 뒤 `mounted` 확인 없이 controller를 비우거나 `setState`를 호출해, 요청 중 뒤로 가면 dispose된 객체를 조작할 수 있다. `lib/features/book_record/screens/widgets/book_info_edit_dialog.dart:66`~`:75`도 이미지 선택 후 같은 문제가 있고 플랫폼 예외를 사용자에게 안내하지 않는다. 아울러 업로드 API가 허용하는 JPEG/PNG/WebP 및 5MB 제한을 선택 단계에서 확인하지 않아, 지원하지 않는 이미지나 큰 사진은 저장 시 일반 400 오류로만 실패한다.
- [중간][월 스크러버 오프셋] `lib/features/bookshelf/screens/widgets/finished_month_index_bar.dart:142`~`:147`은 월 이동 콜백을 먼저 호출한 뒤 스크럽 상태를 알린다. 필터 패널이 열린 경우 부모는 `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:120`~`:126`에서 패널 높이를 포함한 위치로 점프한 다음 `:228`~`:234`에서 패널을 닫는다. 선행 sliver가 사라진 높이만큼 목표 월 위치가 어긋난다.
- [낮음][정적 분석] `flutter analyze`는 오류·경고는 없지만 `prefer_initializing_formals`, `use_null_aware_elements` 정보 22건으로 종료 코드 1을 반환한다. 현재 프로젝트의 완료 조건인 정적 분석을 통과하지 못한 상태다.

## 개선 제안
- 상세 상태가 동기화·로그아웃 이후에도 남음 → record family provider를 화면 수명에 맞게 `autoDispose`하고, 외부 책장 동기화와 로그아웃 시 활성 상세 provider를 무효화한다. 자체 저장에 따른 목록 버전 증가와 외부 동기화 신호를 구분하면 저장 직후 불필요한 재로딩 없이 최신성을 유지할 수 있다.
- PATCH와 DELETE가 동시에 실행됨 → controller에서 mutation을 직렬화하거나 in-flight 중 후속 작업을 거부하고, `state.isLoading` 동안 AppBar 삭제와 모든 수정 진입점을 비활성화한다.
- 포팅 기준의 핵심 화면·라우팅이 빠짐 → 현재 작업 범위를 정보 탭 1차 이관으로 명시할 것이 아니라면 `/records/:id` 라우트와 탭 구조를 먼저 만들고, 메모/독후감/커뮤니티 계열 기능 및 ISBN 연결을 기준 문서 순서대로 이관한다.
- 완독 상태와 페이지가 모순됨 → `totalPages`가 있으면 완독 PATCH에 `currentPage: totalPages`를 함께 전달한다.
- 직접 입력 플랫폼을 복원·삭제할 수 없음 → 옵션에 없는 기존 값은 처음부터 '직접 입력'을 선택하고 입력값을 보존한다. '플랫폼 없음'을 별도 결과로 표현해 빈 문자열을 PATCH하도록 null(변경 없음)과 구분한다.
- 비동기 완료 후 dispose된 위젯을 조작할 수 있고 파일 제약을 늦게 발견함 → 모든 await 뒤 UI 접근 전에 `mounted`를 확인하고 이미지 선택 예외를 인라인 안내한다. 업로드 전 MIME과 파일 크기를 검사해 허용 형식/5MB 제한을 구체적으로 보여준다.
- 패널을 닫은 뒤에도 이전 높이로 월 이동함 → 스크럽 시작 알림을 월 선택보다 먼저 전달해 패널을 닫은 다음 다음 프레임에 오프셋을 계산하거나, 스크럽 중 계산에서는 닫힐 패널 높이를 제외한다.
- 정적 분석이 종료 코드 1임 → 변경된 코드의 22개 info lint를 정리한 뒤 `flutter analyze`가 정상 종료되는지 다시 확인한다.
