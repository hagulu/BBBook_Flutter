# 리뷰 결과

## 요약

- 현재 미커밋 변경사항을 검토한 결과, 태그 관리 시트의 종료 경합 1건, 큰 글자 배율 대응 회귀 2건, 완독 보기 모드 복원의 비동기 경합 1건을 확인했다. `flutter analyze`와 `git diff --check`는 통과했다.
- 코드와 호출 경로를 기준으로 검토했으며 앱 실행·테스트는 수행하지 않았다. 기존 구현 파일은 수정하지 않았다.

## 문제점

- [P2 문제] 태그를 키보드 완료 액션으로 추가한 직후 관리 시트가 의도치 않게 닫힐 수 있다.
  - 위치: `lib/features/book_record/screens/widgets/tag_section.dart:170`, `lib/features/book_record/screens/widgets/tag_section.dart:216`
  - 완료 액션으로 키보드 인셋이 0이 된 동안에는 `_submitting` 조건으로 닫기를 미루지만, 이때 `_keyboardWasVisible`은 계속 `true`로 남는다. 로컬 우선 태그 추가가 끝나면 `_focusNode.requestFocus()` 직후 `finally`에서 `_submitting = false`로 다시 빌드하는데, 키보드 인셋은 동기적으로 복구되지 않는다. 따라서 다음 빌드가 여전히 `bottomInset == 0`인 경우 `maybePop()`이 예약되어, 태그 추가 성공 직후 시트가 닫히는 경합이 남아 있다.

- [P2 문제] 새 책 소개 리치 텍스트가 시스템 글자 크기 설정을 따르지 않는다.
  - 위치: `lib/features/book_detail/screens/book_detail_screen.dart:427`, `lib/features/book_detail/screens/book_detail_screen.dart:437`
  - `RichText`와 `TextPainter`의 기본 `textScaler`는 `TextScaler.noScaling`이다. 이전 `Text` 위젯은 주변 `MediaQuery`의 글자 배율을 적용했지만, 현재 구현은 본문과 5줄 초과 판정을 모두 고정 배율로 렌더링해 큰 글자를 사용하는 사용자에게 책 소개만 작게 보인다. 같은 영역의 `GestureDetector` 기반 `더보기`/`접기`도 텍스트 크기만큼만 탭할 수 있어 최소 터치 영역을 확보하지 못한다.

- [P2 문제] 완독 리스트 모드의 92dp 고정 행이 큰 글자 배율에서 콘텐츠를 수용하지 못한다.
  - 위치: `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:512`, `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:1171`, `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:1200`
  - `SliverFixedExtentList`와 바깥 `SizedBox`가 행 높이를 92dp로 강제하지만 제목·저자/출판사 텍스트는 시스템 배율에 따라 커지고, 카테고리/태그 줄은 다시 22dp로 고정된다. 제목, 부가 정보, 칩이 모두 있는 행은 큰 글자 배율에서 세로 공간을 초과해 `Column` overflow가 발생하거나 칩 텍스트가 잘린다. 이 보기 모드는 이번 변경으로 새로 추가되어 기존 그리드와 달리 접근성 배율에서 사용할 수 없는 상태다.

- [P3 문제] 저장된 완독 보기 모드 로딩이 사용자의 최신 선택을 되돌릴 수 있다.
  - 위치: `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:148`, `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:214`
  - `initState()`의 `_loadViewMode()`가 완료되기 전에 사용자가 보기 버튼을 누르면, 늦게 도착한 저장값이 현재 `_viewMode`를 다시 덮어쓴다. 예를 들어 저장값이 그리드인 상태에서 첫 화면의 버튼을 빠르게 눌러 리스트를 선택하면 화면은 다시 그리드로 돌아가지만, 별도 비동기 저장은 리스트를 기록할 수 있어 현재 화면과 다음 진입 상태도 서로 달라진다. 비동기 복원으로 모드가 바뀌는 경로는 `_resetScroll()`도 호출하지 않아 이미 스크롤한 경우 행 높이 전환에 따른 위치 점프가 추가로 생긴다.

## 개선 제안

- 태그 시트 종료 경합 → 제출 중 관찰한 키보드 종료는 별도 억제 상태로 기록하고, 키보드가 실제로 다시 열린 뒤에만 일반 종료 감지를 재활성화한다. 예약한 닫기 콜백에서도 제출 상태와 억제 상태를 다시 확인해 오래된 프레임의 `maybePop()`이 실행되지 않게 한다.
- 책 소개 글자 배율·터치 영역 → `MediaQuery.textScalerOf(context)`를 `TextPainter`와 `RichText` 양쪽에 동일하게 전달하고, `더보기`/`접기`는 최소 44~48dp 터치 영역과 버튼 semantics를 제공하는 `TextButton` 계열로 구현한다.
- 완독 리스트 고정 높이 → 현재 92dp를 최소 높이로만 사용하거나 글자 배율을 반영한 공통 행 높이를 계산해 `itemExtent`와 월 인덱스 오프셋에 함께 적용한다. 칩 영역도 배율에 따라 높이가 늘어나도록 고정 22dp 제약을 제거하거나 보정한다.
- 보기 모드 복원 경합 → 초기 복원 완료 여부 또는 사용자 변경 세대를 추적해 사용자가 한 번이라도 선택한 뒤에는 늦은 저장값을 적용하지 않는다. 복원으로 레이아웃 모드가 바뀌는 경우에도 스크롤 위치를 함께 초기화하고, 저장 작업은 최신 선택 순서를 보장한다.
