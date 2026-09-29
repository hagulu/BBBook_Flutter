# 리뷰 결과

## 요약

- 현재 작업 트리의 AdMob 배너 도입 변경에서 iOS 광고 요청, 광고 생성 시점, 좁은 화면과 완독 목록 레이아웃에 영향을 주는 문제 5건을 확인했다. `flutter analyze`는 통과했다.

## 문제점

- [P1][iOS에서 Android용 배너 광고 단위 ID 사용] `lib/core/config/ad_config.dart:8`, `lib/shared/widgets/app_banner_ad.dart:52` — 모든 플랫폼이 Android 테스트 배너 ID(`.../6300978111`)로 요청한다. 추가된 iOS App ID는 iOS 테스트 값이지만 배너 단위 ID는 별도다. `google_mobile_ads` 9.1.0의 예제도 iOS 배너에 `.../2934735716`을 사용한다. 따라서 iOS에서 배너 로드가 실패할 수 있으며, 공통 위젯의 실패 처리로 광고가 조용히 사라진다.
- [P2][화면 밖 광고까지 한꺼번에 로드] `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:655-669`, `lib/features/public_bookshelf/screens/public_finished_bookshelf_screen.dart:251-263` — 모든 광고를 `SliverMainAxisGroup`의 `SliverToBoxAdapter` 자식으로 만들어 둔다. 슬리버 자식들은 그리드 항목과 달리 화면 밖에서도 위젯 트리에 생성되므로, `AppBannerAd.initState()`가 각 슬롯의 `BannerAd.load()`를 즉시 호출한다. 완독 책이 많으면 화면 진입 시 광고 요청과 네이티브 광고 객체가 한꺼번에 늘어난다.
- [P2][좁은 화면에서 배너 너비가 영역을 초과] `lib/shared/widgets/app_banner_ad.dart:107-110`, `lib/features/book_search/screens/book_search_screen.dart:194-200` — 광고는 항상 320dp 너비로 요청하지만, 검색 화면은 좌우 16dp씩 패딩한다. 화면 폭이 320dp이면 광고에 주어진 너비는 288dp여서 요청 크기와 실제 표시 영역이 다르다. 작은 기기나 좁은 창에서 광고가 잘릴 수 있다.
- [P2][광고가 로드되지 않으면 완독 그리드 행 간격과 리스트 구분선이 사라짐] `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:641-669`, `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:685-712` — 광고 위치에서 책 목록을 별도의 `SliverGrid` 또는 `SliverFixedExtentList`로 나눈다. 광고가 로드되기 전이나 실패하면 `AppBannerAd`는 높이 0으로 접히지만, 두 그리드 사이에는 기존의 `mainAxisSpacing` 16dp가 없다. 리스트에서도 각 묶음의 마지막 행은 `showDivider: false`라 광고가 없으면 6행마다 구분선이 빠진다.
- [P2][월 인덱스 이동 오프셋에 광고 높이 오차가 누적] `lib/shared/widgets/app_banner_ad.dart:33-34`, `lib/shared/widgets/app_banner_ad.dart:76-77`, `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:379-415` — 스크러버 계산에는 광고 콘텐츠 높이를 항상 70dp로 더하지만, 실제 높이는 `광고` 텍스트의 폰트·텍스트 배율에 따른 줄 높이 + 4dp + 배너 50dp다. 특히 큰 글씨 설정에서 차이가 커지고 이전 월의 광고 슬롯 수만큼 누적되어 선택한 월과 다른 위치로 이동한다.

## 개선 제안

- iOS에서 Android용 배너 광고 단위 ID 사용 → `AdConfig`에서 Android/iOS 배너 단위 ID를 플랫폼별로 선택한다.
- 화면 밖 광고까지 한꺼번에 로드 → 광고 슬롯을 가시 영역에서 지연 생성하는 목록 구조로 바꾸거나, 슬롯별 로드를 화면 가시성에 맞춰 시작·해제한다.
- 좁은 화면에서 배너 너비가 영역을 초과 → 사용 가능한 폭으로 크기를 정하는 적응형 배너를 쓰거나 320dp 미만에서는 광고를 배치하지 않는다.
- 광고가 로드되지 않으면 완독 그리드 행 간격과 리스트 구분선이 사라짐 → 광고 표시 여부와 별개로 책 묶음 사이의 기본 행 간격과 리스트 구분선을 유지한다.
- 월 인덱스 이동 오프셋에 광고 높이 오차가 누적 → 광고가 실제로 그려진 뒤 렌더 높이를 측정해 `_adSlotHeights`에 전달한다.

검증: `flutter analyze` 통과. 프로젝트 지침에 따라 앱과 테스트는 실행하지 않았다.
