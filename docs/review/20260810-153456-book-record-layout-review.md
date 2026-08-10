# 리뷰 결과

## 요약

- 책 기록 화면의 정보 재배치와 상태 선택 다이얼로그 분리는 전반적으로 자연스럽지만, 진행률 슬라이더가 렌더링 assertion을 위반하고 터치 영역도 축소되는 문제가 남아 있다.
- 검증: `flutter analyze`는 `No issues found`로 통과했다. 프로젝트 지침에 따라 앱 실행과 테스트는 수행하지 않았다.

## 문제점

- [문제][높음][렌더링] `lib/features/book_record/screens/widgets/progress_card.dart:139`~`:164`는 트랙 폭을 맞추기 위해 `Padding`에 좌우 `-6`을 전달한다. Flutter의 `RenderPadding`은 모든 inset이 0 이상이어야 한다고 assertion하므로, 총 쪽수가 있는 `READING`/`PAUSED` 책에서 이 분기가 빌드되면 디버그 모드 렌더링 오류가 발생한다. 정적 분석으로는 검출되지 않으며 release에서 assertion이 제거되더라도 음수 padding은 `Padding`의 지원 계약 밖이다.
- [문제][중간][접근성/입력] `lib/features/book_record/screens/widgets/progress_card.dart:145`~`:152`는 thumb 반지름을 6px로 줄이는 동시에 `SliderComponentShape.noOverlay`를 사용한다. 현재 Flutter의 Slider 레이아웃은 overlay와 thumb 중 큰 크기로 자체 높이를 계산하므로 이 조합에서는 슬라이더의 세로 hit 영역이 약 12px까지 줄어든다. 손가락으로 드래그하기 어렵고 포커스·누름 overlay 피드백도 사라져, 모바일 조작 영역으로 충분하지 않다.

## 개선 제안

- 음수 `Padding`으로 트랙을 확장함 → 지원되는 `Slider.padding: EdgeInsets.zero` 또는 커스텀 `SliderTrackShape`로 트랙 좌우 위치를 맞추고, 음수 inset은 제거한다.
- 슬라이더 hit 영역이 thumb 크기까지 축소됨 → 시각적 thumb는 작게 유지하더라도 `SizedBox(height: 48)` 등으로 최소 조작 높이를 보장하고, overlay는 투명도/크기만 조정해 포커스·누름 피드백과 hit 영역을 유지한다.
