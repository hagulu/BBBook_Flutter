import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';

/// 별점 표시(읽기 전용). [rating]은 0.0 ~ 5.0.
///
/// [filledColor]는 별점 출처를 색으로 구분하기 위한 값이다. 기본값(`highlightGold`,
/// 노란색)은 알라딘에서 받아온 회원 평점(책 검색·상세의 `displayRating`) 기준이고,
/// BBBook 서비스 안에서 직접 기록한 값(커뮤니티 리뷰 등)을 표시할 때는 호출부에서
/// `AppColors.accentGraphic`(아이덴티티 컬러 — 옆에 텍스트가 없는 순수 아이콘이라
/// `accentForeground`보다 화사한 톤을 쓴다)를 넘긴다.
class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.size = 16,
    this.filledColor = AppColors.highlightGold,
  });

  final double rating;
  final double size;
  final Color filledColor;

  @override
  Widget build(BuildContext context) {
    final filled = rating.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < filled ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
          size: size,
          color: i < filled ? filledColor : AppColors.border,
        ),
      ),
    );
  }
}

/// 별점 입력(탭으로 0~5 정수 별점 선택, 다시 탭하면 0으로 초기화).
///
/// 항상 BBBook 서비스 안에서 직접 기록하는 "내 평점"이라 채워진 별은 항상
/// 아이덴티티 컬러(`AppColors.accentGraphic`)로 표시한다.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.rating,
    required this.onChanged,
  });

  final double rating;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final filled = rating.round().clamp(0, 5);
    return Semantics(
      label: '내 평점, 5점 중 $filled점',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final starIndex = i + 1;
          return IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: '$starIndex점',
            onPressed: () =>
                onChanged(starIndex == filled ? 0 : starIndex.toDouble()),
            icon: Icon(
              i < filled ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
              color: i < filled ? AppColors.accentGraphic : AppColors.border,
              size: 28,
            ),
          );
        }),
      ),
    );
  }
}
