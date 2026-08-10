# 리뷰 결과

## 요약
- 이전 리뷰의 상세 provider 수명, 저장·삭제 경합, 비동기 생명주기, 이미지 검증, 정적 분석 문제는 개선됐지만, 계정 전환 시 로컬 책장 노출 가능성과 책 기록 포팅 누락·상태 불일치가 남아 있어 현재 변경을 완료 상태로 보기 어렵다.

## 문제점
- [문제][높음][계정 데이터 격리] 앱 시작 중 refresh 또는 `getMe`가 일시적인 네트워크·서버 오류로 실패하면 `lib/features/auth/providers/auth_notifier.dart:52`~`:56`, `:68`~`:75`는 로컬 책장과 refresh token을 보존한 채 로그인 화면을 노출한다. 이 상태에서 다른 계정으로 소셜 로그인해도 `:84`~`:92`는 기존 책장을 비우지 않는다. 로컬 스키마는 `lib/features/bookshelf/data/bookshelf_database.dart:33`~`:83`처럼 사용자 식별자 없이 하나의 `user_book`과 `last_synced_at`을 공유하고, 로그인 후 `lib/features/bookshelf/providers/bookshelf_providers.dart:68`~`:76`의 stale 검사도 이전 계정의 시각을 사용할 수 있다. 따라서 최근 동기화 직후라면 새 계정 화면에 이전 계정 책장이 즉시 표시되고, 증분 동기화가 실행돼도 `lib/features/bookshelf/data/bookshelf_dao.dart:169`~`:200`은 새 계정 응답에 없는 이전 계정 행을 정리하지 않아 노출이 계속될 수 있다.
- [문제][높음][포팅 범위 누락] 기준 문서 `docs/porting-reference/features/book-record.md:5`~`:20`은 `/records/[id]` 진입점, 정보·메모·독후감·커뮤니티·토론·공개 독후감 탭, ISBN 연결 흐름을 책 기록 기능으로 정의한다. 현재 라우터는 `lib/app/router.dart:46`~`:56`의 `/`와 `/feed`만 제공하고, `lib/features/book_record/screens/book_record_screen.dart:154`~`:195`는 정보 일부를 단일 스크롤 화면으로 조립한다. 세 책장 카드도 `MaterialPageRoute`로만 진입하므로 딥 링크와 탭 쿼리 상태가 없고, 메모·독후감·커뮤니티 계열 기능 및 ISBN 검색 연결에 접근할 수 없다.
- [문제][중간][완독 데이터 정합성] `lib/features/book_record/screens/book_record_screen.dart:248`~`:256`은 완독 전환 PATCH에 상태·난이도·별점·한줄평만 보내고, 총 쪽수가 있는 책의 `currentPage`를 `totalPages`로 맞추지 않는다. 기준 프런트 `../../front/bbbook/components/feature/book-detail/BookRecordPage.tsx:774`~`:778`은 완독 처리 시 마지막 쪽을 함께 저장하므로, 현재 앱에서는 300쪽 책이 30쪽인 채 `FINISHED`가 되는 모순된 기록이 남는다.
- [문제][중간][활성 상세 화면 최신성] `lib/app/main_shell.dart:45`~`:54`는 앱 복귀 시 책장 동기화를 수행하고, 변경이 있으면 `lib/features/bookshelf/providers/bookshelf_providers.dart:52`~`:61`에서 동기화 버전을 올린다. 하지만 열려 있는 상세 controller는 `lib/features/book_record/providers/book_record_providers.dart:38`~`:45`에서 그 버전을 의도적으로 구독하지 않는다. 상세 화면이 계속 watch 중이면 `autoDispose`도 동작하지 않으므로, 다른 기기에서 수정·삭제된 책을 동기화해도 현재 상세 화면은 나갔다 다시 들어오기 전까지 이전 값을 보여준다.
- [문제][중간][플랫폼 삭제 불가] `lib/features/book_record/screens/widgets/meta_dialogs.dart:128`~`:141`은 출처를 누를 때 기존 플랫폼 선택을 해제하지만, 같은 출처를 다시 선택한 경우 `:101`~`:114`는 플랫폼 값을 `null`로 남긴다. 호출부의 `lib/features/book_record/screens/book_record_screen.dart:291`~`:295`와 API의 `lib/features/book_record/data/book_record_api.dart:51`~`:61`에서는 null을 요청에서 생략하므로 기존 플랫폼이 유지된다. 별도의 '미설정' 선택지도 없어 전자책·오디오북의 플랫폼을 한 번 저장하면 같은 출처를 유지하면서 지울 수 없다.
- [문제][중간][월 스크러버 오프셋] `lib/features/bookshelf/screens/widgets/finished_month_index_bar.dart:132`~`:147`은 목표 월 이동 콜백을 먼저 실행한 뒤 스크럽 시작을 알린다. 필터 패널이 열려 있으면 부모는 `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:120`~`:126`에서 패널 높이를 포함해 점프하고, 그 후에야 `:228`~`:234`에서 패널을 닫는다. 선행 sliver가 사라진 만큼 목표 월이 위로 이동해 첫 스크럽 위치가 어긋난다.

## 개선 제안
- 일시적인 인증 오류 뒤 다른 계정 로그인 시 이전 책장이 남음 → 로컬 DB에 소유자 user id를 별도로 저장하고 로그인 성공 시 현재 사용자와 비교해 불일치하면 DB·책장 provider·상세 provider를 인증 상태 전환 전에 초기화한다. 소유자를 확인할 수 없는 기존 DB도 안전하게 비운 뒤 전체 동기화를 시작한다.
- 책 기록 기준 기능과 라우팅이 일부만 구현됨 → 현재 범위를 '정보 화면 1차 이관'으로 명시할 것이 아니라면 `/records/:id` 라우트와 탭 상태부터 추가하고, 메모·독후감·ISBN 연결·ISBN 기반 커뮤니티 탭을 기준 문서 순서대로 이관한다.
- 완독 상태와 현재 쪽수가 모순될 수 있음 → `totalPages`가 있을 때 완독 PATCH에 `currentPage: totalPages`를 함께 전달한다.
- 앱 복귀 동기화가 열린 상세에 반영되지 않음 → 자체 저장용 목록 갱신과 외부 동기화 완료 신호를 분리하고, 상세 controller는 외부 동기화 신호에만 반응해 해당 로컬 행을 다시 읽거나 삭제 상태를 반영한다.
- 같은 출처에서 플랫폼을 지울 수 없음 → 플랫폼 목록에 '미설정'을 추가하고 이를 선택하면 API가 null 저장으로 해석하는 빈 문자열을 명시적으로 PATCH한다. null은 계속 '변경 없음' 의미로 구분한다.
- 필터 패널 높이를 포함한 위치로 이동한 뒤 패널이 닫힘 → 스크럽 시작 알림을 월 선택보다 먼저 보내 패널을 닫고 다음 프레임에 오프셋을 계산하거나, 스크럽 이동 계산에서 닫힐 패널 높이를 처음부터 제외한다.
