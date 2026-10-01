# 리뷰 결과

## 요약
- 현재 작업 트리의 징계 상태·공개 기능 제한 변경분에서 P1 1건과 P2 2건을 확인했다. `flutter analyze`는 통과했으며, 프로젝트 규칙에 따라 앱 실행과 테스트 실행은 하지 않았다.

## 문제점
- [P1][징계가 해제돼도 공개 기능 사용 권한이 복구되지 않음] [auth_notifier.dart:547](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/auth/providers/auth_notifier.dart:547), [auth_access_providers.dart:25](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/auth/providers/auth_access_providers.dart:25) — 새 사용자 재조회는 `403 USER_SANCTIONED` 응답에서만 호출된다. 징계 상태를 한 번 읽은 뒤 기간이 만료되거나 관리자가 해제해도 앱 복귀·기록 동기화·토큰 갱신은 기존 `state.user`를 유지한다. 작성·수정 버튼은 숨겨지고 공개 토글도 막혀 있어 해당 기능에서 재조회를 유발할 요청을 보낼 수 없다. 따라서 정상 사용자가 앱을 재시작하거나 재로그인하기 전까지 독자평·토론·답변 작성, 공개 독후감 수정, 완독 책장 공개를 계속 제한받는다. `/api/users/me` 문서는 기간제 징계가 `endsAt` 경과 후 1분 이내에 해제된다고 명시한다.
- [P2][징계 중에도 토론 마감일 수정 메뉴가 열림] [discussion_detail_screen.dart:702](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/discussion/screens/discussion_detail_screen.dart:702) — `canEdit` 조건은 일반 수정 메뉴에만 적용되고 바로 아래의 ‘마감일 설정/수정’ 메뉴는 항상 생성된다. 징계 중인 작성자가 이 메뉴에서 날짜를 변경하거나 제거하면 `DiscussionApi.patchClosesAt()`이 동일한 `PATCH /api/discussions/{topicId}`로 `closesAt`을 전송한다. 해당 API 문서는 징계 중 수정 필드를 전달하면 `403 USER_SANCTIONED`로 거부한다고 규정하므로, 이미 제한 상태를 아는 사용자에게 성공할 수 없는 편집 흐름을 제공한다.
- [P2][큰 글씨 설정에서 징계 상세 내용을 끝까지 읽을 수 없음] [sanction_detail_screen.dart:28](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/profile/screens/sanction_detail_screen.dart:28) — 본문 전체가 스크롤 없는 `Padding → Column`에 들어 있다. 작은 화면에서 글씨를 크게 설정하면 제목·해제 시각·제한 안내의 줄 수가 늘어 본문 높이를 초과하지만, 아래 내용을 볼 이동 수단이 없다. 예를 들어 320×568 논리 픽셀 화면과 2배 텍스트 배율에서는 징계 정보와 안내가 가용 높이를 넘는 구조다. 정적 레이아웃 검토로 확인한 항목이며 앱을 실행해 재현하지는 않았다.

## 개선 제안
- 징계 해제 상태 갱신 누락 → 앱 복귀나 징계 상세 진입 시 현재 사용자 정보를 재조회하고, 기간제 징계는 `endsAt` 이후 서버 상태를 다시 확인하도록 연결한다. 재조회한 `isSanctioned`로 권한 provider와 로컬 캐시를 갱신한다.
- 토론 마감일 수정 제한 누락 → 마감일 설정/수정 메뉴에도 `canEdit` 조건을 적용하고, 마감일 저장 직전에도 현재 작성 권한을 확인한다.
- 징계 상세 본문 넘침 → 본문을 `SafeArea`와 `SingleChildScrollView`로 감싸 글씨 크기와 화면 높이에 관계없이 모든 안내를 읽을 수 있게 한다.
