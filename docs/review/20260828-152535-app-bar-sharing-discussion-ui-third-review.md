# 리뷰 결과

## 요약
- 선택지 추가 UI와 포커스 흐름은 개선됐지만, 직전 재리뷰의 선택지 최대 개수 경계 조건과 상대 시각 갱신 문제 2건은 아직 남아 있다.

## 문제점
- [문제][중간][선택지가 이미 5개인 토론에 편집 가능한 6번째 항목이 계속 생성됨] 시트를 열 때 현재 controller 수와 잠긴 선택지 수가 같으면 빈 draft를 무조건 추가한다. 기존 선택지가 최대치인 5개여도 이 초기 추가 경로는 `kMaxDiscussionOptions` 검사를 거치지 않으므로 6번째 입력창이 만들어지고 자동 포커스까지 받는다. 제목의 `+` 버튼은 5개 제한을 지키지만 자동 생성된 6번째 항목에는 적용되지 않는다. 사용자가 값을 입력해 저장하면 원본에도 6개가 반영되고 `_canSubmit` 검증에 걸려 수정 버튼만 비활성화되며, 시트 안에서는 저장을 막거나 원인을 안내하지 않는다. (`lib/features/discussion/utils/discussion_poll.dart:6`, `lib/features/discussion/screens/discussion_form_screen.dart:99`, `lib/features/discussion/screens/discussion_form_screen.dart:303`, `lib/features/discussion/screens/discussion_form_screen.dart:304`, `lib/features/discussion/screens/discussion_form_screen.dart:314`, `lib/features/discussion/screens/discussion_form_screen.dart:352`, `lib/features/discussion/screens/discussion_form_screen.dart:374`)
- [문제][낮음][상대 작성 시각이 화면을 연 시점의 값으로 계속 고정됨] 30일 미만 작성 시각은 초·분·시간 단위 상대값으로 계산되지만, 표시 위젯은 여전히 `StatelessWidget`이고 목록·상세 화면에 주기적인 갱신 장치가 없다. 화면에 계속 보이는 항목은 `0초 전` 같은 문구가 수분 뒤에도 갱신되지 않는다. (`lib/features/discussion/utils/discussion_date.dart:21`, `lib/features/discussion/screens/widgets/discussion_common.dart:74`, `lib/features/discussion/screens/widgets/discussion_common.dart:108`, `lib/features/discussion/screens/widgets/discussion_topic_card.dart:79`)

## 개선 제안
- 최대 개수에서 생성되는 6번째 draft → 초기 빈 항목도 `draftControllers.length < kMaxDiscussionOptions`일 때만 추가한다. 저장 직전에도 비어 있지 않은 선택지 수를 검증해 최대치를 넘는 draft가 원본에 반영되지 않도록 한다.
- 갱신되지 않는 상대 시각 → 절대 시각 표기를 유지하거나, 상대 시각을 계속 표시한다면 필요한 최소 주기로 다시 빌드하는 공용 위젯을 사용한다. 초 단위 정확도가 필요하지 않다면 `방금 전`처럼 시간 경과에 덜 민감한 문구를 사용한다.
