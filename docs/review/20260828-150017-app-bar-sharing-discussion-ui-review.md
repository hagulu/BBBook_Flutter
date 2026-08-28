# 리뷰 결과

## 요약
- 공통 앱바와 생각나눔 진입 구조는 대체로 일관되지만, 토론 작성 상태가 의도치 않게 바뀌는 문제와 상대 시각·탭 피드백 문제를 보완해야 한다.

## 문제점
- [문제][중간][선택지 관리 화면을 열기만 해도 자유 토론 등록이 막힘] 선택지가 없는 상태에서 선택지 관리 바텀시트를 열면 빈 `TextEditingController`를 즉시 원본 폼 상태에 추가한다. 이제 선택지 존재 여부 자체가 선택지 토론 모드이므로, 사용자가 아무것도 입력하지 않고 시트를 뒤로 닫거나 드래그해 내려도 `_useOptions`가 `true`로 남고 빈 선택지 검증에 걸려 등록 버튼이 비활성화된다. 사용자는 시트를 다시 열어 빈 항목을 직접 삭제해야 자유 토론을 등록할 수 있다. (`lib/features/discussion/screens/discussion_form_screen.dart:59`, `lib/features/discussion/screens/discussion_form_screen.dart:127`, `lib/features/discussion/screens/discussion_form_screen.dart:320`)
- [문제][낮음][상대 작성 시각이 화면을 연 시점의 값으로 고정됨] 새 포맷터는 30일 미만 작성 시각을 초·분·시간 단위 상대값으로 계산하지만, 이를 사용하는 `DiscussionAuthorRow`는 `StatelessWidget`이고 목록·상세 화면 어디에도 주기적으로 다시 빌드하는 장치가 없다. 따라서 방금 작성된 항목이 화면에 계속 보이면 `0초 전` 같은 문구가 수분 뒤에도 그대로 남는다. (`lib/features/discussion/utils/discussion_date.dart:21`, `lib/features/discussion/screens/widgets/discussion_common.dart:74`, `lib/features/discussion/screens/widgets/discussion_common.dart:108`, `lib/features/discussion/screens/widgets/discussion_topic_card.dart:79`)
- [문제][낮음][공용 진입 버튼의 잉크 피드백이 카드 배경 뒤에 가려짐] `EntryButton`은 불투명한 `Container` 기반 `RecordSectionCard` 안에 `InkWell`을 직접 배치한다. `InkWell`의 스플래시는 가장 가까운 상위 `Material`에 그려지므로 그 사이의 불투명한 카드 장식 뒤에 가려지고, 생각나눔 탭에 새로 추가된 세 버튼과 책 상세 진입 버튼에서 탭 피드백이 보이지 않는다. (`lib/features/book_record/screens/widgets/entry_button.dart:23`, `lib/features/book_record/screens/widgets/entry_button.dart:25`, `lib/features/book_record/screens/book_sharing_list.dart:31`, `lib/features/book_detail/screens/widgets/community_reviews_section.dart:260`)

## 개선 제안
- 선택지 관리 진입 시 원본 상태 변경 → 시트 전용 임시 controller 목록을 만들고 닫힐 때 유효한 변경만 원본에 반영하거나, 최초 빈 항목을 추가했더라도 값 없이 시트가 닫히면 자동으로 제거한다.
- 갱신되지 않는 상대 시각 → 절대 시각 표기를 유지하거나, 상대 시각을 계속 보여야 한다면 필요한 최소 주기로 행을 다시 빌드하는 타이머/공용 위젯을 사용한다. 초 단위 정확도가 필요하지 않다면 `방금 전`처럼 시간 경과에 덜 민감한 문구도 함께 고려한다.
- 보이지 않는 탭 피드백 → `EntryButton` 안에서 투명한 `Material`과 클립된 `InkWell`을 카드 장식 위에 두거나 카드 배경을 `Ink`/`Material`로 그려 스플래시가 표면 위에 렌더링되게 한다.
