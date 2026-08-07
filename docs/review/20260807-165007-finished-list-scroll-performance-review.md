# 리뷰 결과

## 요약
- 완독 목록은 책 카드를 지연 생성하고 있어 기본 목록 구조는 적절하지만, 표지 원본 해상도 디코딩과 스크롤 중 타이머 재생성이 체감 저하의 가장 유력한 원인이며 월별 sliver 누적은 데이터가 많을 때 보조 병목이 될 수 있다.

## 문제점
- [높음] `lib/features/bookshelf/screens/widgets/book_cover.dart:22`의 `Image.network`에 `cacheWidth`/`cacheHeight`가 없어, 화면에는 약 3열 썸네일 크기로 표시하면서도 서버 원본 크기로 이미지를 디코딩한다. 완독 목록을 스크롤해 새 카드가 계속 나타나면 큰 이미지의 디코딩과 GPU 업로드가 프레임 안에서 반복되고, 디코딩된 원본이 Flutter 메모리 이미지 캐시를 빠르게 차지해 퇴출·재디코딩 가능성도 커진다. 표지가 표시되는 모든 책장 탭에 영향을 주지만, 항목이 누적되는 완독 탭에서 특히 체감되기 쉽다.
- [중간] `lib/features/bookshelf/screens/widgets/finished_month_index_bar.dart:75`의 스크롤 리스너는 스크롤 알림마다 `setState`를 호출한 뒤 `_scheduleAutoHide()`를 실행하며, `:88`에서 기존 `Timer`를 취소하고 새 `Timer`를 만든다. 60/120Hz 스크롤 동안 프레임마다 타이머 객체가 생성·취소되어 불필요한 할당과 GC 부담이 발생한다. 썸 위치 갱신은 필요하지만 자동 숨김 예약까지 매번 갱신할 필요는 없다.
- [조건부/중간] `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:290`은 월마다 `SliverToBoxAdapter`와 `SliverGrid`를 각각 생성한다. 책 카드는 `SliverChildBuilderDelegate`로 지연 생성되므로 전체 책을 한 번에 빌드하는 문제는 없지만, 완독 기록의 월 수에 비례해 sliver/render object 수가 늘어난다. 기록이 여러 해 쌓인 사용자에서는 뷰포트 레이아웃 탐색 비용이 커질 수 있다.

## 개선 제안
- 원본 해상도 이미지 디코딩 → `BookCover`가 실제 레이아웃 폭과 `devicePixelRatio`로 목표 픽셀 폭을 계산해 `Image.network(cacheWidth: ...)`에 전달한다. 높이는 표지 비율에 맞춰 한 축만 지정해도 되며, 지나치게 낮은 고정값 대신 기기 배율을 반영해야 선명도를 유지할 수 있다. 이 항목을 가장 먼저 적용한 뒤 profile 모드의 DevTools Performance/Memory에서 빠른 스크롤 시 raster frame과 이미지 캐시 사용량을 비교한다.
- 스크롤마다 자동 숨김 타이머 재생성 → 스크롤 시작 시 타이머를 한 번 취소하고, 스크롤 중에는 썸 위치만 갱신하며, `ScrollEndNotification` 또는 `ScrollPosition.isScrollingNotifier`가 종료를 알릴 때만 숨김 타이머를 한 번 예약한다. 작은 인덱스 위젯의 `setState`는 유지해도 되며, 먼저 타이머 할당만 제거하는 것이 범위가 작다.
- 월별 sliver 누적 → 앞의 두 항목 적용 후에도 완독 월 수가 많은 데이터에서 layout 병목이 확인될 때만 진행한다. 월 헤더와 3권 단위 행을 하나의 평탄한 delegate로 만들어 단일 `SliverList`에서 지연 생성하면 월 수에 따른 sliver 증가를 없앨 수 있다. 이 변경은 월 점프 오프셋 계산도 함께 맞춰야 하므로 측정 없이 선행하지 않는다.
- 적용 우선순위는 `표지 디코딩 크기 제한 → 자동 숨김 타이머 1회 예약 → 월별 sliver 평탄화(프로파일 확인 후)`가 적절하다. `finishedBooksProvider`의 로컬 DB 조회와 `_groupByMonth`는 필터/동기화 등 상태 변경 시 실행되며 일반 스크롤 프레임마다 실행되지 않으므로 이번 스크롤 튜닝 대상에서는 제외한다.
