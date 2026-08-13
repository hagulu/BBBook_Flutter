# 리뷰 결과

## 요약

- 저자 표시 가공과 다이얼로그의 바텀시트 전환은 정적 분석을 통과했지만, 공통 바텀시트 셸의 안전 영역 배치 때문에 하단 안전 영역이 있는 기기에서 시트 배경이 끊기는 문제가 있다.
- 검증: `flutter analyze`는 `No issues found`로 통과했고 `git diff --check`에서도 공백 오류가 없었다. 프로젝트 지침에 따라 앱 실행과 테스트는 수행하지 않았다.

## 문제점

- [문제][중간][화면/안전 영역] `lib/features/book_record/screens/widgets/record_dialog_shell.dart:41`~`:57`은 투명한 `Material` 아래에서 `SafeArea`가 흰색 `Container`를 감싸도록 구성한다. `showModalBottomSheet`는 기본적으로 하단 안전 영역을 제거하지 않으므로, 홈 인디케이터가 있는 iOS 기기 등에서는 `SafeArea`가 컨테이너 아래에 여백을 만들고 그 영역에 흰 시트 배경이 아니라 반투명 모달 배리어가 노출된다. 이번 변경에서 모든 기록·검색·리뷰 폼이 이 셸을 사용하는 바텀시트로 전환되어 같은 시각 회귀가 공통으로 발생한다.

## 개선 제안

- 흰색 컨테이너 바깥에 `SafeArea` 배치 → 흰색 배경과 상단 모서리를 가진 컨테이너가 화면 하단까지 이어지게 하고, 컨테이너 내부 콘텐츠에만 하단 안전 영역 패딩을 적용한다. 예를 들어 `Container`가 `SafeArea(top: false)`를 감싸게 구조를 뒤집거나, `MediaQuery.viewPaddingOf(context).bottom`을 기존 하단 콘텐츠 패딩에 반영한다.
