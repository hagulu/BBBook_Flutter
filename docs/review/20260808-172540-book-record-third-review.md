# 리뷰 결과

## 요약
- 책 기록 정보 편집 범위는 넓어지고 정적 분석도 통과하지만, 계정 경계를 넘는 로컬 데이터 재생성 가능성 2건과 다중 클라이언트 데이터 규격 불일치, 기존 포팅·상태 정합성 문제가 남아 있다.

## 문제점
- [문제][높음][계정 전환 데이터 격리] 앱 시작 중 refresh 또는 `getMe`가 일시적인 오류로 실패하면 `lib/features/auth/providers/auth_notifier.dart:52`~`:56`, `:68`~`:75`는 refresh token과 로컬 책장을 보존한 채 로그인 화면을 노출한다. 이어 다른 계정으로 로그인해도 `:84`~`:92`는 기존 책장을 비우지 않는다. 로컬 DB는 `lib/features/bookshelf/data/bookshelf_database.dart:33`~`:83`처럼 사용자 식별자 없이 모든 계정이 같은 행과 `last_synced_at`을 공유하므로, 새 계정의 `syncIfStale`이 이전 동기화 시각 때문에 생략되거나 증분 동기화만 실행되면 이전 계정 책이 그대로 노출된다.
- [문제][높음][로그아웃 후 이전 계정 기록 부활] 일반 기록 수정은 `lib/features/book_record/screens/book_record_screen.dart:40`~`:44`에서 화면 본문만 로딩 오버레이로 막아 AppBar·시스템 뒤로 가기는 계속 가능하다. 사용자가 저장 중 화면을 나가 로그아웃하면 `lib/features/auth/providers/auth_notifier.dart:153`~`:165`가 DB와 provider를 초기화하지만, 이미 시작된 `lib/features/book_record/providers/book_record_providers.dart:136`~`:149`의 Future는 취소되지 않는다. 이후 이전 계정 API 응답이 도착하면 `lib/features/book_record/data/book_record_repository.dart:128`~`:135`가 초기화된 DB에 그 책을 다시 upsert한다. 동기화에는 `BookshelfDatabase.sessionGeneration` 검사가 있지만 책 기록 PATCH·태그 추가/삭제·로컬 삭제에는 같은 세션 검사가 없어, 로그아웃 또는 새 로그인 뒤 이전 계정 데이터가 되살아날 수 있다.
- [문제][높음][포팅 범위 누락] 기준 문서 `docs/porting-reference/features/book-record.md:5`~`:20`은 `/records/[id]` 라우트, 정보·메모·독후감·커뮤니티·토론·공개 독후감 탭과 ISBN 연결을 책 기록 기능으로 정의한다. 현재 `lib/app/router.dart:46`~`:56`에는 `/`와 `/feed`만 있고, `lib/features/book_record/screens/book_record_screen.dart:154`~`:210`은 정보 화면만 구성한다. 책장 카드의 `MaterialPageRoute` 진입만 가능해 딥 링크·탭 쿼리 상태가 없고, 메모·독후감·ISBN 검색 연결 및 ISBN 기반 커뮤니티 기능에 접근할 수 없다.
- [문제][중간][난이도 데이터 규격 불일치] `lib/features/book_record/models/record_labels.dart:65`~`:74`는 표시 문구인 `쉬움/보통/어려움`을 선택값과 API 저장값으로 함께 사용하고, `lib/features/book_record/screens/book_record_screen.dart:324`~`:330`과 완독 팝업이 이를 그대로 PATCH한다. 기준 클라이언트는 `../../front/bbbook/components/feature/book-detail/BookRecordPage.tsx:119`~`:127`처럼 `EASY/MODERATE/HARD`를 저장하고 한글은 표시할 때만 매핑한다. 따라서 기존 `EASY` 데이터는 Flutter 상세와 `lib/features/bookshelf/screens/widgets/finished_filter_panel.dart:84`~`:90`에서 영문 원문으로 보이고 선택 상태도 복원되지 않으며, Flutter에서 저장한 한글 값은 같은 의미의 별도 필터 값으로 쌓인다.
- [문제][중간][완독 데이터 정합성] `lib/features/book_record/screens/book_record_screen.dart:263`~`:271`은 완독 전환 시 상태·난이도·별점·한줄평만 보내고, 총 쪽수가 있는 책의 `currentPage`를 `totalPages`로 맞추지 않는다. 기준 프런트 `../../front/bbbook/components/feature/book-detail/BookRecordPage.tsx:774`~`:778`은 마지막 쪽을 함께 저장하므로, 현재 앱에서는 일부만 읽은 페이지 수와 `FINISHED` 상태가 동시에 남는다.
- [문제][중간][활성 상세 화면 최신성] 앱 복귀 동기화가 로컬 DB를 변경하면 `lib/features/bookshelf/providers/bookshelf_providers.dart:52`~`:61`이 동기화 버전을 올리지만, 상세 controller는 `lib/features/book_record/providers/book_record_providers.dart:38`~`:45`에서 그 신호를 구독하지 않는다. 화면이 열려 있는 동안에는 `autoDispose`도 실행되지 않아, 다른 기기에서 수정·삭제된 책을 동기화해도 현재 상세 화면은 나갔다 다시 들어오기 전까지 이전 값을 보여준다.
- [문제][중간][플랫폼 삭제 불가] `lib/features/book_record/screens/widgets/meta_dialogs.dart:128`~`:141`은 출처를 누를 때 플랫폼 선택을 해제하지만, 같은 출처를 다시 선택하면 `:101`~`:114`가 `platformName`을 null로 남긴다. null은 `lib/features/book_record/data/book_record_api.dart:54`~`:67`에서 요청에서 생략되므로 기존 값이 유지되고, 별도의 '미설정' 선택지도 없다. 전자책·오디오북의 플랫폼을 한 번 저장하면 출처를 유지한 채 삭제할 수 없다.
- [문제][중간][월 스크러버 오프셋] `lib/features/bookshelf/screens/widgets/finished_month_index_bar.dart:132`~`:147`은 목표 월 이동을 먼저 실행한 뒤 스크럽 시작을 알린다. 필터 패널이 열려 있으면 부모는 `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:120`~`:126`에서 패널 높이를 포함한 위치로 점프한 후 `:228`~`:234`에서 패널을 닫으므로, 사라진 선행 sliver 높이만큼 첫 스크럽 위치가 어긋난다.
- [문제][중간][접근성] `lib/features/book_record/screens/widgets/star_rating.dart:43`~`:57`의 별점 버튼은 의미 라벨이 없고 터치 영역이 32dp이며, `lib/features/book_record/screens/widgets/icon_option_selector.dart:35`~`:47`과 `lib/features/book_record/screens/widgets/reading_status_selector.dart:21`~`:34`은 선택 상태를 색상으로만 전달한다. 태그 삭제 버튼도 `lib/features/book_record/screens/widgets/tag_section.dart:211`~`:218`처럼 약 22dp의 라벨 없는 아이콘이다. 스크린 리더 사용자는 각 별의 점수와 현재 선택 상태, 태그 삭제 대상을 알기 어렵고 모바일 권장 터치 영역보다 작아 오조작 가능성이 높다.

## 개선 제안
- 일시적 인증 오류 뒤 다른 계정 로그인 시 이전 책장이 남음 → 로컬 DB에 소유자 user id를 저장하고 로그인 성공 시 사용자와 비교해 불일치하거나 소유자를 확인할 수 없으면, 인증 상태 전환 전에 DB와 책장·상세 provider를 초기화한 뒤 전체 동기화한다.
- 로그아웃 전에 시작한 기록 요청이 DB를 다시 채움 → 모든 책 기록 mutation 시작 시 `sessionGeneration`을 캡처하고 API 완료 후 로컬 upsert/delete 전에 동일한지 검사한다. provider dispose 시 요청 취소도 연결하되, 서버 요청 취소 여부와 무관하게 세션 검사를 최종 쓰기 방어선으로 둔다.
- 책 기록 기준 기능과 라우팅이 일부만 구현됨 → 현재 작업이 정보 화면 1차 범위로 명시된 것이 아니라면 `/records/:id` 라우트와 탭 상태부터 추가하고 메모·독후감·ISBN 연결·ISBN 기반 커뮤니티 탭을 기준 문서 순서대로 이관한다.
- 표시용 난이도 문구가 저장값으로 섞임 → `apiValue(EASY/MODERATE/HARD)`와 `label(쉬움/보통/어려움)`을 분리한 enum/모델을 사용하고, PATCH·필터 조건에는 API 값을, UI에는 라벨을 사용한다. 이미 저장된 한글 값은 조회 시 호환 매핑하거나 데이터 정리 방안을 함께 정한다.
- 완독 상태와 페이지가 모순될 수 있음 → `totalPages`가 있으면 완독 PATCH에 `currentPage: totalPages`를 함께 전달한다.
- 앱 복귀 동기화가 열린 상세에 반영되지 않음 → 자체 저장으로 발생하는 목록 갱신과 외부 동기화 완료 신호를 분리하고, 상세 controller는 외부 신호에서 해당 로컬 행만 다시 읽어 수정·삭제 상태를 반영한다.
- 같은 출처에서 플랫폼을 지울 수 없음 → 플랫폼 목록에 '미설정'을 추가하고 선택 시 문서상 null 저장 의미인 빈 문자열을 명시적으로 PATCH해 null(변경 없음)과 구분한다.
- 필터 패널 높이를 포함해 이동한 뒤 패널이 닫힘 → 스크럽 시작을 월 선택보다 먼저 전달해 패널을 닫고 다음 프레임에 위치를 계산하거나, 스크럽 중 오프셋에서는 닫힐 패널 높이를 제외한다.
- 선택·삭제·별점 조작이 스크린 리더와 작은 터치 영역에 취약함 → 선택 위젯에 `Semantics(button: true, selected: ...)`를, 별점·삭제 버튼에는 대상이 드러나는 label/tooltip을 제공하고 최소 44~48dp 터치 영역을 확보한다.
