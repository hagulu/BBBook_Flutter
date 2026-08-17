# 리뷰 결과

## 요약
- 색상 토큰 전환과 호출부 치환은 정적 분석을 통과했지만, 비활성·보조·햇살 색상을 텍스트와 활성 컨트롤에 적용한 일부 조합은 접근성 대비 기준을 충족하지 못한다.

## 문제점
- [높음][접근성] `AppColors.inactive`(`#97A99A`)는 흰색 표면에서 대비가 2.48:1, 앱 배경에서 2.35:1에 불과하다. 그런데 `lib/app/main_shell.dart:127`의 이동 가능한 미선택 하단 탭 아이콘·12px 라벨, `lib/features/book_detail/screens/widgets/review_item.dart:86`과 `:114`의 메뉴·신고 버튼처럼 비활성화되지 않은 컨트롤에도 사용된다. `lib/features/book_record/screens/widgets/record_field_tile.dart:65`에서는 `미설정` 같은 실제 읽기 텍스트에도 사용되어, 활성 UI 그래픽 3:1 및 일반 텍스트 4.5:1 기준을 모두 충족하지 못한다.
- [중간][접근성] `AppColors.textMuted`(`#63756A`)와 `AppColors.surfaceAlt`(`#ECF2E5`)의 대비는 4.30:1이다. 전역 입력 필드의 13px 라벨·힌트(`lib/core/theme/app_theme.dart:126-129`)와 12px 미선택 필터/카테고리 칩(`lib/features/bookshelf/screens/widgets/finished_filter_panel.dart:190-202`, `lib/features/book_record/screens/widgets/book_category_field.dart:170-193`)이 이 조합을 사용하므로 일반 텍스트 4.5:1 기준에 미달한다.
- [중간][접근성] `AppColors.sunlight`(`#BF7E08`)는 앱 배경에서 대비가 3.21:1인데 `lib/features/book_record/screens/book_record_screen.dart:161-168`의 11px `명작` 라벨 텍스트에 직접 사용된다. 별·왕관 같은 그래픽 강조에는 충분하지만 작은 텍스트 색상으로는 4.5:1 기준을 충족하지 못한다.

## 개선 제안
- `inactive`를 실제 disabled/decorative 상태에만 한정하고, 이동·메뉴·신고처럼 동작 가능한 미선택 컨트롤과 `미설정` 텍스트는 최소한 `textMuted` 이상의 대비를 갖는 색으로 표시한다. 토큰을 계속 공용으로 사용할 경우 흰색과 앱 배경 모두에서 텍스트 4.5:1을 만족하도록 값을 조정한다.
- `textMuted`를 `surfaceAlt` 위에서도 4.5:1 이상이 되도록 조금 어둡게 조정하거나, 입력·칩의 작은 텍스트에 `textBody`를 사용한다.
- `명작` 라벨은 `textStrong` 같은 읽기용 텍스트 색으로 분리하고, `sunlight`는 왕관 아이콘 등 비텍스트 강조에만 유지한다.
