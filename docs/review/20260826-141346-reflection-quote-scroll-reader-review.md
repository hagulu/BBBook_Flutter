# 리뷰 결과

## 요약
- 인용 부호 오버레이의 `Stack`이 무제한 세로 제약에서 일반 자식으로 레이아웃되어, 인용 부호 누락·편집 스크롤 불능·리더 화면 레이아웃 파손을 함께 유발할 수 있는 상태다.

## 문제점
- [문제][높음] `ReflectionQuillEditor`의 바깥 `Stack`에서 `ValueListenableBuilder`가 일반(non-positioned) 자식이고, 그 builder가 위치 지정 자식만 가진 또 다른 `Stack`을 반환한다. 작성 화면과 리더 모두 상위 `SingleChildScrollView` 때문에 이 위젯에 세로 최대 높이가 무한대로 전달될 수 있다. 위치 지정 자식만 가진 내부 `Stack`은 자체 높이를 산출할 일반 자식이 없어 무한 높이를 선택하게 되고, 바깥 `Stack`의 크기 계산과 Quill 본문 높이를 오염시킨다. 그 결과 인용 부호가 표시되지 않거나, 작성 화면의 스크롤 범위가 만들어지지 않거나, 읽기 화면에서 레이아웃 예외로 화면이 깨질 수 있다. (`lib/features/book_reflection/screens/book_reflection_editor_screen.dart:203`, `lib/features/book_reflection/screens/book_reflection_editor_screen.dart:214`, `lib/features/book_reflection/screens/book_reflection_editor_screen.dart:580`, `lib/features/book_reflection/screens/book_reflection_detail_screen.dart:257`, `lib/features/book_reflection/screens/book_reflection_detail_screen.dart:387`)

## 개선 제안
- 인용 오버레이를 바깥 `Stack`의 크기 계산에서 제외하도록 `ValueListenableBuilder`를 `Positioned.fill` 안에 배치한다. 그러면 바깥 `Stack`의 높이는 Quill 본문만으로 결정되고, 오버레이는 그 확정된 영역을 사용한다.
- 오버레이 내부 `Stack`에는 확정된 유한 제약을 전달하고 `clipBehavior: Clip.none`을 적용해 왼쪽 여백에 배치한 인용 부호가 잘리지 않게 한다.
- 작성 화면의 기존 외부 `SingleChildScrollView`와 공유 `ScrollController` 구조는 유지하되, 오버레이가 본문 크기에 관여하지 않게 한 뒤 긴 본문·연속 인용·인용 포함 리더 화면을 함께 확인한다.
