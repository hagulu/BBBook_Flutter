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
/// 아이콘과 함께 한눈에 비교하게 보여준다). 선택된 카드만 파란 보더 + 옅은
/// 강조 배경으로 두드러지게 한다.
class IconOptionSelector<T> extends StatelessWidget {
  const IconOptionSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<IconOption<T>> options;
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
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
                  ? AppColors.accentLight.withValues(alpha: 0.35)
                  : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  option.icon,
                  size: option.iconSize,
                  color: selected ? AppColors.primary : AppColors.mutedIcon,
                ),
                const SizedBox(height: 4),
                Text(
                  option.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? AppColors.primary : AppColors.bodyText,
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
