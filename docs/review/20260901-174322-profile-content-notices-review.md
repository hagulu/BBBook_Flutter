# 리뷰 결과

## 요약
- `flutter analyze`는 통과했지만, 로컬 저장 데이터 삭제 경고와 독후감 상세 ID 연결에 높은 위험의 회귀 2건이 있고 프로필 하위 화면의 이동·갱신·스포일러 처리에도 실제 동작 문제 5건이 있다.

## 문제점
- [문제] [높음] `lib/features/profile/screens/profile_screen.dart:480`은 로그아웃 버튼을 누른 순간 처음으로 `storageModeProvider`를 `read`한 뒤 `valueOrNull`을 확인한다. 이 provider는 `lib/features/storage_mode/providers/storage_mode_providers.dart:21`의 비동기 `FutureProvider`이므로 아직 다른 화면에서 구독하지 않았다면 최초 값은 `AsyncLoading`이고, 실제 저장 모드가 로컬이어도 `isLocal`이 `false`가 된다. 설정 화면을 먼저 열지 않고 바로 로그아웃하면 서버 모드용 문구만 표시된 뒤 `AuthNotifier.logout()`이 유일한 로컬 사본을 삭제할 수 있어, 이전 리뷰에서 지적한 비가역 데이터 삭제 경고가 여전히 보장되지 않는다.
- [문제] [높음] `lib/features/profile/screens/my_reflections_screen.dart:51`은 `/api/me/reflections`가 준 서버 독후감 ID를 `lib/features/profile/screens/my_reflections_screen.dart:72`에서 그대로 `BookReflectionDetailScreen.reflectionId`에 넘기지만, 로컬 모델은 `lib/features/book_reflection/models/book_reflection.dart:3`처럼 `id`(로컬 PK)와 `serverId`를 분리하고 로컬 생성 행은 push 뒤에도 음수 `id`를 유지한다. 상세 provider가 최종적으로 `lib/features/book_reflection/data/book_reflection_dao.dart:51`의 `id = ?`로 조회하므로 앱에서 작성해 동기화한 독후감은 서버 ID와 로컬 ID가 달라 "찾을 수 없음"으로 끝난다. 또한 `lib/features/profile/screens/my_reflections_screen.dart:56`은 API 규격상 정상일 수 있는 `isbn13 == null` 독후감도 로컬 책 조회 전에 바로 실패시키므로 유효한 항목이 탭 가능한 카드로 보이면서 열리지 않는다.
- [문제] [보통] `lib/features/discussion/screens/discussion_detail_screen.dart:347`은 강조 대상 답변이 현재 `items`에 이미 들어 있을 때만 스크롤을 예약한다. 답변 provider는 `lib/features/discussion/providers/discussion_providers.dart:274`에서 최신 20개만 최초 조회하고 다음 페이지는 사용자가 하단까지 스크롤해야 `loadMore()`가 호출된다. 따라서 "내가 작성한 토론 댓글"에서 오래된 댓글을 탭하면 그 댓글이 2페이지 이후에 있는 동안 자동 조회·이동이 전혀 일어나지 않아, `highlightAnswerId` 진입 계약이 사실상 첫 페이지 항목에만 동작한다.
- [문제] [보통] `lib/features/profile/screens/my_discussions_screen.dart:45`와 `lib/features/profile/screens/my_discussion_answers_screen.dart:46`은 상세 화면 push 결과를 기다리지 않고 목록 provider도 갱신하지 않는다. 아래 라우트는 계속 마운트되어 autoDispose 목록 캐시가 유지되는 반면, 상세의 수정·삭제는 `lib/features/discussion/screens/discussion_detail_screen.dart:145`, `lib/features/discussion/screens/discussion_detail_screen.dart:230`, `lib/features/discussion/screens/discussion_detail_screen.dart:285`에서 상세/답변 provider만 바꾼다. 사용자가 토론 제목·상태·댓글을 수정하거나 삭제하고 돌아오면 목록에는 이전 내용이나 이미 삭제된 카드가 그대로 남는다.
- [문제] [보통] `docs/porting-reference/my-content-screens.md` §3-2는 리뷰 카드의 책 표지와 제목을 ISBN 책 상세로 연결하도록 명시하고 `MyContentCardLayout`도 `lib/features/profile/screens/widgets/my_content_card_layout.dart:33`에 이를 위한 `onBookTap`을 제공한다. 그러나 `lib/features/profile/screens/widgets/my_review_card.dart:24`는 콜백을 전달하지 않고 `lib/features/profile/screens/my_reviews_screen.dart:116`에도 `BookDetailScreen` 이동이 없어, 정상 리뷰에서도 사용자가 책 상세로 갈 수 없다. 리뷰 자체의 상세 화면이 없다는 사실과 책 상세 이동이 없다는 것은 별개다.
- [문제] [보통] `lib/features/profile/screens/profile_screen.dart:204`의 독서 통계 카드는 화살표와 버튼 semantics를 노출하면서 `onTap: () {}`만 실행한다. 포팅 기준의 독서 리포트 화면이 아직 프로젝트에 없다면, 현재 UI는 탭 가능한 카드처럼 보이지만 아무 반응도 하지 않는 상태다.
- [문제] [보통] `MyDiscussionSummary.isSpoiler`는 응답에서 파싱되지만 `lib/features/profile/screens/widgets/my_discussion_card.dart:65`는 이 값을 확인하지 않고 `previewText`를 그대로 표시한다. 일반 토론 목록의 `DiscussionTopicCard`는 같은 플래그가 켜진 경우 본문을 "스포일러가 포함된 토론입니다"로 가리므로, 프로필의 내 토론 목록을 통해서는 사용자가 보호하려던 스포일러 내용이 즉시 노출된다.
- [문제] [낮음] 공지사항 API는 인증 불필요하고 토큰 재발급 흐름도 없어야 하지만 `lib/features/notices/providers/notices_providers.dart:13`은 인증 요청 전용 `apiClientProvider`를 주입한다. 그 결과 `lib/core/network/api_client.dart:44`에서 불필요한 access token이 공개 요청에도 첨부되고, 공지사항 요청의 401도 refresh 및 전역 로그아웃 경로를 탈 수 있어 공개 API 계약과 다르게 동작한다.
- [문제] [낮음] `lib/features/notices/screens/notices_list_screen.dart:111`은 무한 스크롤 목록을 `ListView.builder`가 아니라 하나의 `Column` 자식으로 만들고 `lib/features/notices/screens/notices_list_screen.dart:125`에서 누적된 모든 행을 매번 즉시 빌드한다. 페이지가 쌓일수록 화면 밖 공지까지 전부 렌더링되어 커서 무한 스크롤의 지연 생성 이점을 잃는다.

## 개선 제안
- 로컬 모드 로그아웃 경고 → 확인창을 띄우기 전에 `storageModeStoreProvider.isLocal()`을 `await`하거나 화면에서 `storageModeProvider`를 지속 구독해 실제 모드가 확정된 뒤 로그아웃을 허용한다.
- 내 독후감 상세 연결 → 서버 ID로 로컬 `book_reflection.server_id` 행을 조회해 실제 로컬 `id`와 `userBookId`를 얻은 뒤 상세 화면에 전달한다. ISBN을 로컬 행 식별자로 사용하지 않아 ISBN이 없는 독후감도 열리게 한다.
- 댓글 하이라이트 → 대상 ID가 현재 페이지에 없고 `hasNext`가 true이면 다음 페이지를 순차 조회해 찾은 후 한 번만 `ensureVisible`을 실행하고, 끝까지 없을 때는 별도 안내로 종료한다.
- 내 토론·댓글 목록 최신화 → 상세 route를 `await`한 뒤 해당 my-content provider를 invalidate하거나, 상세 수정·삭제 성공 시 호출부가 판별할 수 있는 결과를 반환해 필요한 목록만 다시 조회한다.
- 리뷰의 책 이동 → `MyReviewCard`에 책 탭 콜백을 전달하고 `review.isbn13`으로 `BookDetailScreen`을 연다. 카드 본문은 현재처럼 비이동 영역으로 유지한다.
- 독서 통계 무반응 카드 → 독서 리포트 화면을 이번 범위에 포함해 연결하거나, 별도 구현 전까지는 화살표·버튼 semantics·터치 효과를 제거해 정적 요약 카드로 표시한다.
- 내 토론 스포일러 → 일반 토론 카드와 같은 규칙으로 스포일러 배지를 표시하고 펼치기 전에는 `previewText` 대신 보호 문구를 렌더링한다.
- 공개 공지 API → Authorization/401 인터셉터가 없는 별도 공개 Dio를 주입해 문서의 비인증 호출 계약을 지킨다.
- 공지사항 긴 목록 → 행 단위 `ListView.builder`/sliver 구조로 바꿔 화면 주변 항목만 지연 생성하되, 첫·마지막 행의 카드 모서리와 행 구분선은 index로 유지한다.
