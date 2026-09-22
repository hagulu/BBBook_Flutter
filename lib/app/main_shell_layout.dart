import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 플로팅 하단 메뉴와 탭 콘텐츠가 공유하는 레이아웃 기준.
abstract final class MainShellNavigationLayout {
  static const controlSize = 60.0;
  static const outerInset = 6.0;
  static const itemMinHeight = 48.0;
  static const labelFontSize = 13.0;
  static const iconSize = 20.0;
  static const iconLabelGap = 8.0;
  static const controlGap = 8.0;
  static const itemHorizontalPadding = 12.0;
  static const stackedItemHorizontalPadding = 8.0;
  static const stackedItemVerticalPadding = 6.0;
  static const stackedIconLabelGap = 4.0;
  static const minimumHorizontalInset = 16.0;
  static const minimumBottomInset = 16.0;

  /// 안전 영역 위로 메뉴를 조금 더 띄우는 추가 여백. 홈 인디케이터가 있는
  /// 기기에서는 `minimumBottomInset`이 이미 안전 영역에 묻히므로,
  /// 최소값이 아니라 더해지는 값으로 둬야 실제로 위로 올라간다.
  static const bottomLift = 12.0;
  static const contentGap = 12.0;

  /// 현재 화면 폭과 글자 크기에서 가로형 탭이 넘치는지 판단한다.
  static bool usesStackedLabels(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final scaledLabelSize = mediaQuery.textScaler.scale(labelFontSize);
    final horizontalInset =
        math.max(mediaQuery.viewPadding.left, minimumHorizontalInset) +
        math.max(mediaQuery.viewPadding.right, minimumHorizontalInset);
    final availableWidth = mediaQuery.size.width - horizontalInset;

    // 두 레이블은 모두 한글 2글자다. 글자 하나의 폭을 스케일된
    // fontSize로 보수적으로 잡아 렌더링 전에 오버플로를 피한다.
    final estimatedItemWidth =
        (itemHorizontalPadding * 2) +
        iconSize +
        iconLabelGap +
        (scaledLabelSize * 2);
    final estimatedTotalWidth =
        controlSize + controlGap + (outerInset * 2) + (estimatedItemWidth * 2);
    return estimatedTotalWidth > availableWidth;
  }

  /// 큰 글자에서 아이콘과 레이블을 세로로 배치한 실제 메뉴 높이.
  static double navigationHeight(BuildContext context) {
    if (!usesStackedLabels(context)) return controlSize;

    final scaledLabelHeight = MediaQuery.textScalerOf(
      context,
    ).scale(labelFontSize);
    return math.max(
      controlSize,
      (outerInset * 2) +
          (stackedItemVerticalPadding * 2) +
          iconSize +
          stackedIconLabelGap +
          scaledLabelHeight,
    );
  }

  /// 스크롤의 마지막 콘텐츠가 메뉴 위로 완전히 올라오는 하단 여백.
  static double contentBottomPadding(BuildContext context) {
    final safeBottom = math.max(
      MediaQuery.paddingOf(context).bottom,
      minimumBottomInset,
    );
    return navigationHeight(context) + safeBottom + bottomLift + contentGap;
  }
}
