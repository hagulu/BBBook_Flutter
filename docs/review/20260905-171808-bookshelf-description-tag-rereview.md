# 리뷰 결과

## 요약

- 직전 리뷰의 태그 시트 종료 경합, 책 소개 글자 배율, 보기 모드 복원 경합은 해소됐지만, 완독 목록에는 큰 글자 배율 문제 2건이 남아 있고 책 소개 토글의 스크린 리더 라벨이 중복된다. `flutter analyze`와 `git diff --check`는 통과했다.
- 코드와 호출 경로를 기준으로 재검토했으며 앱 실행·테스트는 수행하지 않았다. 기존 구현 파일은 수정하지 않았다.

## 문제점

- [P2 문제] 완독 리스트 행이 시스템 글자 배율을 1.3으로 제한한다.
  - 위치: `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:64`, `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:1221`
  - 행 높이를 108dp로 늘려 기존 overflow는 피했지만, 행 전체를 새 `MediaQuery`로 감싸 1.3을 넘는 사용자 설정을 강제로 낮춘다. 따라서 제목·저자·출판사·카테고리·태그뿐 아니라 표지 대체 텍스트까지 다른 화면보다 작게 표시된다. 시스템에서 더 큰 글자를 선택한 사용자가 필요한 배율을 이 보기에서만 받을 수 없어 직전 접근성 지적은 부분적으로만 해소된 상태다.

- [P2 문제] 월 고정 헤더가 큰 글자에서 세로로 잘린다.
  - 위치: `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:665`, `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:677`
  - `SliverPersistentHeader`의 높이는 항상 44dp인데 내부 패딩이 위 16dp, 아래 8dp를 차지해 월 라벨에는 20dp만 남는다. 라벨은 리스트 행과 달리 시스템 글자 배율을 그대로 따르므로 약 1.4배 이상에서 필요한 줄 높이가 20dp를 넘고, `Text`가 고정 header extent 안에서 잘리거나 다음 콘텐츠와 겹친다. 새 sticky header와 월 이동 오프셋이 같은 고정 상수에 묶여 있어 단순히 텍스트만 확대할 수 없는 구조다.

- [P3 문제] 책 소개 더보기 토글의 접근성 라벨이 중복된다.
  - 위치: `lib/features/book_detail/screens/book_detail_screen.dart:449`, `lib/features/book_detail/screens/book_detail_screen.dart:463`
  - 바깥 `Semantics`가 `설명 더보기`/`설명 접기` 라벨을 제공하지만 `excludeSemantics`를 사용하지 않아, 안쪽 `InkWell`의 탭 semantics와 보이는 `더보기`/`접기` 텍스트도 하위 semantics로 남는다. 스크린 리더는 커스텀 라벨과 화면 텍스트를 한 노드에 합치거나 연속 노드로 읽어 같은 동작명을 중복 안내할 수 있다.

## 개선 제안

- 리스트 행 배율 제한 → 원래 `TextScaler`를 유지하고 현재 108dp를 최소 높이로 사용한다. 고정 extent가 필요하면 실제 시스템 배율을 반영한 공통 행 높이를 계산해 `itemExtent`와 월 이동 오프셋에 동일하게 적용한다.
- 월 헤더 잘림 → 시스템 배율로 계산한 라벨 높이와 세로 패딩을 기준으로 header extent를 산출하고, 같은 값을 delegate와 월 이동 오프셋 계산에 함께 전달한다.
- 더보기 semantics 중복 → 커스텀 라벨을 유지한다면 자식 semantics를 제외하고 같은 semantics 노드에 탭 액션과 펼침 상태를 제공한다. 또는 커스텀 라벨을 제거하고 보이는 버튼 텍스트 하나만 접근성 이름으로 사용한다.
