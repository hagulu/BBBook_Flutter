import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';

/// 별점 표시(읽기 전용). [rating]은 0.0 ~ 5.0.
class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({super.key, required this.rating, this.size = 16});

  final double rating;
  final double size;

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
          color: i < filled ? AppColors.starFilled : AppColors.border,
        ),
      ),
    );
  }
}

/// 별점 입력(탭으로 0~5 정수 별점 선택, 다시 탭하면 0으로 초기화).
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
              color: i < filled ? AppColors.starFilled : AppColors.border,
              size: 28,
            ),
          );
        }),
      ),
    );
  }
}
