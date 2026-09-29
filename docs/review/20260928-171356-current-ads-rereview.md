# 리뷰 결과

## 요약

- 이전 광고 리뷰의 5건 중 3건은 수정됐으며, 화면 밖 광고 일괄 로드·좁은 화면 배너 폭 문제 2건이 남아 있고 월별 그리드의 광고 행 계산 문제 1건을 추가로 확인했다. `flutter analyze`는 통과했다.

## 문제점

- [P2][화면 밖 광고를 모두 동시에 로드] `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:665-683`, `lib/features/public_bookshelf/screens/public_finished_bookshelf_screen.dart:252-269`, `lib/shared/widgets/app_inline_banner_ad.dart:44-47` — 광고 슬롯마다 `SliverToBoxAdapter` 자식으로 `AppInlineBannerAd`를 만들고, 각 위젯의 `initState()`에서 바로 `BannerAd.load()`를 호출한다. `SliverMainAxisGroup`의 자식은 그리드 카드처럼 지연 생성되지 않아, 완독 책이 많으면 화면 밖 슬롯의 광고 요청과 네이티브 광고 객체까지 한꺼번에 생성된다. 새 인라인 위젯도 이전 리뷰의 이 문제를 해결하지 않았다.
- [P2][좁은 화면에서 320dp 배너가 잘릴 수 있음] `lib/shared/widgets/app_banner_ad.dart:123-127`, `lib/shared/widgets/app_inline_banner_ad.dart:115-124`, `lib/features/book_search/screens/book_search_screen.dart:195-201` — 두 배너 위젯 모두 `AdSize.banner`의 320dp 폭을 고정으로 사용한다. 검색 화면은 좌우 16dp 패딩이 있어 화면 폭이 320dp이면 실제 광고 영역은 288dp다. 요청한 광고 크기와 표시 가능한 크기가 달라 작은 화면이나 좁은 창에서 광고가 잘릴 수 있다.
- [P2][월별 그리드의 실제 행 수보다 늦게 광고가 삽입됨] `lib/features/bookshelf/services/finished_grid_ad_layout.dart:31-50`, `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:363-374` — 6행 간격을 `3열 × 6행 = 18권`으로 계산해 월 경계를 넘어 책 수만 누적한다. 월마다 별도의 `SliverGrid`가 새 행에서 시작하므로 일부만 찬 마지막 행도 실제 화면에서는 한 행이다. 예를 들어 8권인 달과 11권인 달이 이어지면 18번째 책 뒤 광고가 나오기 전 실제로는 3행 + 4행, 총 7행이 표시된다. 여러 달에 책이 조금씩 있는 경우 광고 간격은 더 길어진다.

## 개선 제안

- 화면 밖 광고를 모두 동시에 로드 → 광고 슬롯이 가시 영역에 들어올 때 `BannerAd`를 생성·로드하고, 멀어지면 해제하거나 재사용한다.
- 좁은 화면에서 320dp 배너가 잘릴 수 있음 → 실제 사용 가능한 폭으로 적응형 배너 크기를 요청하고, 지원하지 않는 폭에서는 광고를 숨긴다.
- 월별 그리드의 실제 행 수보다 늦게 광고가 삽입됨 → 월별 그리드가 차지하는 `ceil(책 수 / 3)`행을 누적해 광고 경계를 정한다. 리스트 모드는 현재의 책 수 기준을 유지할 수 있다.

검증: `flutter analyze` 통과. 프로젝트 지침에 따라 앱과 테스트는 실행하지 않았다.
