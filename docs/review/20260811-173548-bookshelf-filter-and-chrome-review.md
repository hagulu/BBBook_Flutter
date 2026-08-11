# 리뷰 결과

## 요약

- 완독 필터의 다중 카테고리 `IN` 조회와 고정 난이도 매핑은 데이터 계층까지 일관되게 연결되어 있으나, 탭 바 숨김 상태 복원·카테고리 색상 캐시 갱신·아이콘 터치 영역에 개선이 필요하다.
- 검증: `flutter analyze`는 `No issues found`로 통과했다. 프로젝트 지침에 따라 앱 실행과 테스트는 수행하지 않았다.

## 문제점

- [문제][중간][상태/탭 이동] `lib/features/bookshelf/screens/bookshelf_screen.dart:29`~`:33`의 `TabController`에는 탭 변경 listener가 없고, `:53`~`:65`의 `_chromeVisible`은 현재 탭에서 발생한 세로 `UserScrollNotification`으로만 바뀐다. 한 탭을 아래로 스크롤해 탭 바를 숨긴 뒤 가로 스와이프로 스크롤 위치가 0인 다른 탭이나 빈 탭으로 이동하면 세로 알림이 발생하지 않아 `AnimatedAlign`의 `heightFactor`가 계속 0으로 남는다. 이 상태에서는 새 탭이 맨 위여도 주 탐색용 탭 바를 탭할 수 없고, 사용자가 다시 세로 제스처를 해야만 복구된다.
- [문제][낮음][캐시/표시 정합성] `lib/features/bookshelf/screens/widgets/finished_filter_panel.dart:22`~`:26`은 카테고리 색상 점을 `bookCategoriesProvider`에서 가져오지만, 해당 provider는 `lib/features/bookshelf/providers/bookshelf_providers.dart:31`~`:42`에서 성공 직후 `keepAlive()`되어 값을 계속 유지한다. 반면 로그인 시 `lib/features/auth/providers/auth_notifier.dart:179`~`:184`의 강제 갱신은 DB만 교체하고 provider를 갱신하지 않는다. 이전 앱 세션의 로컬 캐시를 provider가 먼저 읽은 뒤 비동기 강제 갱신이 완료되면, 이번에 추가된 필터 색상 점을 포함한 구독 화면은 새 카테고리 이름/색상을 세션 동안 반영하지 못할 수 있다.
- [문제][낮음][접근성/입력] `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:510`~`:575`의 새 아이콘 바는 검색·공개 설정 버튼을 36×36, 도움말 버튼을 32×32로 강제해 모바일 최소 터치 영역보다 작다. 특히 검색은 완독 필터 진입의 주 동작이라 오조작 가능성이 있고, 도움말 버튼에는 `tooltip`도 없어 스크린 리더 사용자가 누르기 전에 용도를 알기 어렵다.

## 개선 제안

- 탭별 세로 알림만으로 전역 탭 바 가시성을 유지함 → `TabController`의 탭 변경을 감지해 새 탭 진입 시 `_chromeVisible`을 `true`로 복원하거나, 활성 탭의 실제 스크롤 위치에 따라 가시성을 다시 계산한다.
- 로그인 강제 갱신이 DB만 바꾸고 keep-alive provider 값을 남김 → `refreshCategories()` 성공 후 `bookCategoriesProvider`를 invalidate하여 구독 화면이 갱신된 DB 값을 다시 읽게 하거나, 강제 갱신 결과 자체를 provider 상태의 source of truth로 반영한다.
- 아이콘의 시각 크기와 터치 영역을 함께 축소함 → 아이콘 크기는 유지하되 기본 `IconButton` 제약 또는 최소 44~48dp의 별도 hit 영역을 사용하고, 도움말에는 `완독 책장 공개 안내`처럼 동작을 설명하는 `tooltip`을 추가한다.
