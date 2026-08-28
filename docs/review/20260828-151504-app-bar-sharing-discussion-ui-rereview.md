# 리뷰 결과

## 요약
- 직전 리뷰의 선택지 원본 상태 오염과 진입 버튼 피드백은 해결됐지만, 선택지 최대 개수 경계 조건과 상대 시각 갱신 문제 2건이 남아 있다.

## 문제점
- [문제][중간][선택지가 이미 5개인 토론에 편집 가능한 6번째 항목이 생성됨] 선택지 시트를 열 때 현재 controller 수와 잠긴 선택지 수가 같으면 빈 draft를 무조건 하나 추가한다. 기존 선택지가 최대치인 5개여도 이 경로는 `kMaxDiscussionOptions` 검사를 거치지 않아 6번째 입력창이 자동 포커스와 함께 노출된다. 사용자가 값을 입력하고 저장하면 원본에도 6개가 반영되고, 이후 `_canSubmit`의 최대 개수 검증에 걸려 수정 버튼만 비활성화된다. 시트 안에서는 저장이 허용되므로 사용자는 비활성화 원인을 알기 어렵고, 다시 시트를 열어 6번째 항목을 삭제해야 한다. (`lib/features/discussion/utils/discussion_poll.dart:6`, `lib/features/discussion/screens/discussion_form_screen.dart:99`, `lib/features/discussion/screens/discussion_form_screen.dart:302`, `lib/features/discussion/screens/discussion_form_screen.dart:303`, `lib/features/discussion/screens/discussion_form_screen.dart:313`, `lib/features/discussion/screens/discussion_form_screen.dart:343`, `lib/features/discussion/screens/discussion_form_screen.dart:363`)
- [문제][낮음][상대 작성 시각이 화면을 연 시점의 값으로 고정됨] 30일 미만 작성 시각을 초·분·시간 단위 상대값으로 계산하지만, 이를 표시하는 `DiscussionAuthorRow`는 `StatelessWidget`이고 목록·상세 화면에 주기적인 갱신 장치가 없다. 화면에 계속 보이는 항목은 `0초 전` 같은 문구가 수분 뒤에도 그대로 남는다. (`lib/features/discussion/utils/discussion_date.dart:21`, `lib/features/discussion/screens/widgets/discussion_common.dart:74`, `lib/features/discussion/screens/widgets/discussion_common.dart:108`, `lib/features/discussion/screens/widgets/discussion_topic_card.dart:79`)

## 개선 제안
- 최대 개수에서 생성되는 6번째 draft → 자동 빈 항목은 `draftControllers.length < kMaxDiscussionOptions`일 때만 추가하고, 시트 저장 시에도 비어 있지 않은 선택지 수가 최대치를 넘으면 반영하지 않도록 검증한다.
- 갱신되지 않는 상대 시각 → 절대 시각 표기를 유지하거나, 상대 시각을 계속 표시한다면 필요한 최소 주기로 행을 다시 빌드하는 공용 위젯을 사용한다. 초 단위 갱신이 필요하지 않다면 `방금 전`처럼 시간 경과에 덜 민감한 문구를 사용할 수 있다.
