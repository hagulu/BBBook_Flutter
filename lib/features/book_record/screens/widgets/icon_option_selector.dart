import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// [IconOptionSelector] 한 항목(값 + 아이콘 + 라벨).
class IconOption<T> {
  const IconOption({
    required this.value,
    required this.icon,
    required this.label,
    this.iconSize = 20,
  });

  final T value;
  final IconData icon;
  final String label;
  final double iconSize;
}

/// 단일 선택 아이콘 카드 그룹(독서 상태/난이도/출처처럼 소수의 고정 선택지를
/// 아이콘과 함께 한눈에 비교하게 보여준다). 선택된 카드만 강조색 보더 + 옅은
/// 강조 배경으로 두드러지게 한다. [crossAxisCount]를 지정하면 같은 카드
/// 디자인을 여러 행의 균일한 그리드로 배치한다.
class IconOptionSelector<T> extends StatelessWidget {
  const IconOptionSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.crossAxisCount,
    this.childAspectRatio = 1.5,
  });

  final List<IconOption<T>> options;
  final T? selected;
  final ValueChanged<T> onSelected;
  final int? crossAxisCount;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    final columns = crossAxisCount;
    if (columns != null) {
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: childAspectRatio,
        children: [
          for (final option in options)
            _OptionCell(
              option: option,
              selected: option.value == selected,
              onTap: () => onSelected(option.value),
            ),
        ],
      );
    }

    return Row(
      children: [
        for (final option in options) ...[
          if (option != options.first) const SizedBox(width: 8),
          Expanded(
            child: _OptionCell(
              option: option,
              selected: option.value == selected,
              onTap: () => onSelected(option.value),
            ),
          ),
        ],
      ],
    );
  }
}

/// 명작/또 볼래처럼 값이 예/아니오뿐인 독립 토글 카드. [IconOptionSelector]와
/// 같은 시각 언어(보더 + 선택 시 강조 배경)를 쓰지만, 여러 옵션이 값 하나를
/// 공유하는 선택 그룹이 아니라 각자 자기 상태를 갖는 boolean 토글이라 별도
/// 위젯으로 둔다.
class BoolIconOption extends StatelessWidget {
  const BoolIconOption({
    super.key,
    required this.label,
    required this.value,
    required this.filledIcon,
    required this.regularIcon,
    required this.activeColor,
    required this.onChanged,
    this.iconSize = 22,
  });

  final String label;
  final bool value;
  final IconData filledIcon;
  final IconData regularIcon;
  final Color activeColor;
  final ValueChanged<bool> onChanged;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      label: label,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              color: value
                  ? activeColor.withValues(alpha: 0.12)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: value ? activeColor : AppColors.border,
                width: value ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  value ? filledIcon : regularIcon,
                  size: iconSize,
                  color: value ? activeColor : AppColors.controlInactive,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: value ? FontWeight.bold : FontWeight.w500,
                    color: value ? activeColor : AppColors.textBody,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionCell<T> extends StatelessWidget {
  const _OptionCell({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final IconOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accentSurface.withValues(alpha: 0.35)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.accentForeground : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  option.icon,
                  size: option.iconSize,
                  color: selected
                      ? AppColors.accentForeground
                      : AppColors.controlInactive,
                ),
                const SizedBox(height: 4),
                Text(
                  option.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected
                        ? AppColors.accentForeground
                        : AppColors.textBody,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
