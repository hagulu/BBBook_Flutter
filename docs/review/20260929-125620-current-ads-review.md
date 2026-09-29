# 리뷰 결과

## 요약

- 이전 리뷰의 광고 로드 시점·좁은 화면 폭·월별 행 계산은 보완됐지만, 긴 목록의 광고 객체 보유와 글자 크기 변경 후 월 이동 오차, 릴리스 광고 ID 설정 문제 3건이 남아 있다. `flutter analyze`는 통과했다.

## 문제점

- [P1][릴리스에서도 테스트 광고 ID 사용] `lib/core/config/ad_config.dart:13-21`, `android/app/src/main/AndroidManifest.xml:86-91`, `ios/Runner/Info.plist:59-60` — Android/iOS App ID와 배너 광고 단위 ID가 모두 Google 테스트 값으로 고정돼 있다. 릴리스 빌드에서 이 값을 검사하거나 교체하는 경로가 없어 현재 설정으로 배포하면 실제 광고 수익이 발생하지 않는다. 코드의 TODO는 교체 필요성을 표시하지만 배포 누락을 막지는 못한다.
- [P2][완독 목록을 스크롤할수록 광고 객체 누적] `lib/shared/widgets/app_inline_banner_ad.dart:84-89`, `lib/shared/widgets/app_inline_banner_ad.dart:135-139`, `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:685-703`, `lib/features/public_bookshelf/screens/public_finished_bookshelf_screen.dart:263-280` — 광고 로드는 슬롯이 뷰포트에 가까워질 때 시작하지만, 한 번 로드한 뒤에는 스크롤 감시를 해제하고 `BannerAd`를 위젯이 폐기될 때까지 보유한다. 완독 그리드의 광고 슬롯은 `SliverMainAxisGroup` 안의 고정 자식이어서 화면 밖으로 나가도 상태가 유지된다. 책이 많은 목록을 끝까지 탐색하면 지나온 슬롯 수만큼 네이티브 광고 객체가 남는다.
- [P2][글자 크기 변경 후 월 이동 위치가 어긋남] `lib/shared/widgets/app_inline_banner_ad.dart:55-67`, `lib/features/bookshelf/screens/widgets/finished_tab_view.dart:396-433` — 인라인 광고 높이는 최초 레이아웃에서 한 번만 측정한다. 앱 사용 중 시스템 글자 크기가 바뀌면 `광고` 라벨과 슬롯의 실제 높이는 다시 계산되지만 `_adSlotHeights`에는 이전 높이가 남는다. 완독 책장의 월 인덱스를 누르면 앞선 광고 슬롯 수만큼 오차가 누적된다.

## 개선 제안

- 릴리스에서도 테스트 광고 ID 사용 → 플랫폼별 실제 App ID와 광고 단위 ID를 릴리스 설정으로 주입하고, 릴리스 빌드가 테스트 ID를 사용하면 빌드 단계에서 확인하도록 한다.
- 완독 목록을 스크롤할수록 광고 객체 누적 → 화면에서 충분히 멀어진 슬롯의 `BannerAd`를 해제하거나, 동시에 유지하는 광고 수에 상한을 둔다.
- 글자 크기 변경 후 월 이동 위치가 어긋남 → `MediaQuery`의 텍스트 배율이 바뀌면 레이아웃 후 슬롯 높이를 다시 측정해 `_adSlotHeights`에 전달한다.

검증: `flutter analyze` 통과. 프로젝트 지침에 따라 앱과 테스트는 실행하지 않았다.
