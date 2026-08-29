# 리뷰 결과

## 요약
- `flutter analyze`는 통과했지만, 공개 독후감의 숨김 필터·페이지네이션 결합과 공감 연속 입력에서 실제 상태 불일치가 발생할 수 있고 공용 UI의 시간·터치 접근성도 보완이 필요하다.

## 문제점
- [문제][중간][숨김 필터 후 첫 결과가 화면을 채우지 못하면 다음 페이지를 열 수 없음] `PublicReflectionService.getPage()`는 서버 페이지에서 공개 항목을 하나라도 찾는 즉시 반환한다. 예를 들어 20개 중 19개가 숨김이고 공개 글 1개만 남은 페이지가 `hasNext=true`이면 화면에는 스크롤되지 않는 카드 1개만 표시된다. 다음 조회는 `ScrollController`의 스크롤 리스너에서만 시작하므로, 특히 픽셀 이동이 생기지 않는 Android의 짧은 목록에서는 `_onScroll()`이 호출되지 않아 뒤 페이지의 공개 독후감에 도달할 수 없다. 현재 서비스 테스트의 “숨김 항목뿐인 페이지 다음에 공개 항목 1개·hasNext=true” 사례도 화면에 연결하면 같은 상태를 만든다. (`lib/features/public_reflection/services/public_reflection_service.dart:41`, `lib/features/public_reflection/services/public_reflection_service.dart:54`, `lib/features/public_reflection/screens/public_reflection_list_screen.dart:45`, `lib/features/public_reflection/screens/public_reflection_list_screen.dart:141`)
- [문제][중간][공감 버튼 연속 탭 시 서버와 화면의 최종 상태가 달라질 수 있음] `toggleLike()`에는 진행 중 요청을 막거나 직렬화하는 장치가 없고, 리더의 공감 버튼도 요청 중 계속 활성화되어 있다. 첫 탭의 POST와 두 번째 탭의 DELETE가 동시에 실행되면 각 완료 콜백이 자신이 시작될 때의 `wasLiked`를 기준으로 최신 상태를 다시 덮어쓴다. 서버 처리 순서와 응답 도착 순서가 달라지는 경우 마지막 응답이 이전 의도를 화면에 복원해 서버의 실제 공감 여부와 불일치한다. (`lib/features/public_reflection/providers/public_reflection_providers.dart:138`, `lib/features/public_reflection/providers/public_reflection_providers.dart:149`, `lib/features/public_reflection/providers/public_reflection_providers.dart:153`, `lib/features/public_reflection/screens/public_reflection_reader_screen.dart:91`, `lib/features/public_reflection/screens/public_reflection_reader_screen.dart:145`)
- [문제][낮음][상대 작성 시각이 화면을 연 시점에 고정됨] 공개 독후감 리더와 토론 상세·답변은 `formatDiscussionDateTime()`으로 초·분·시간 단위 상대 시각을 만들지만, 이를 표시하는 화면과 `CommunityAuthorRow`에는 시간 경과에 따른 재빌드가 없다. 따라서 화면을 계속 열어 두면 `0초 전`이나 `1분 전` 같은 값이 실제 시간이 지나도 갱신되지 않는다. (`lib/features/public_reflection/screens/public_reflection_reader_screen.dart:133`, `lib/features/discussion/utils/discussion_date.dart:21`, `lib/shared/widgets/community_content.dart:139`)
- [문제][낮음][공용 공감 버튼의 터치 높이가 최소 권장 영역보다 작음] `CommunityLikeButton`은 15px 아이콘에 상하 7px 패딩만 적용되어 실제 높이가 약 29px이고 최소 높이 제약도 없다. 공개 독후감·토론 주제·답변에서 같은 위젯을 공유하므로 세 화면 모두 44px 수준의 기본 터치 영역을 확보하지 못해 작은 화면이나 운동 제약이 있는 사용자에게 조작이 어렵다. (`lib/shared/widgets/community_content.dart:363`, `lib/shared/widgets/community_content.dart:378`, `lib/shared/widgets/community_content.dart:381`)

## 개선 제안
- 숨김 필터 후 짧아지는 페이지 → 서비스가 공개 항목을 `size`만큼 모으거나 마지막 페이지에 도달할 때까지 다음 커서를 이어서 조회한다. 화면에서 보완한다면 첫 레이아웃 뒤 `hasNext`인데 스크롤 범위가 없을 때 자동으로 `loadMore()`를 이어 호출한다.
- 공감 요청 경합 → 컨트롤러에 요청 진행 상태를 두어 완료 전 재입력을 막고 버튼도 비활성 상태로 표시하거나, 사용자의 최신 목표 상태를 기준으로 요청을 직렬화해 이전 응답이 최신 의도를 덮어쓰지 못하게 한다.
- 갱신되지 않는 상대 시각 → 절대 시각을 사용하거나, 상대 시각을 유지한다면 분 단위 등 필요한 최소 주기로 공용 작성자 행을 다시 빌드한다.
- 작은 공감 터치 영역 → 시각 크기는 유지하되 `ConstrainedBox` 또는 외부 패딩으로 최소 44×44px 터치 영역을 보장하고 공감 여부를 `Semantics`의 토글 상태로 함께 전달한다.
