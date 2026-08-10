import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 앱 전역 필 스타일 선택 칩(둥근 필, 선택 시 primary 배경 + 흰 텍스트).
/// 책장 완독 필터의 `_FilterChip`과 같은 시각 언어를 공유하되, 아이콘을
/// 함께 둘 수 있게 확장했다. Flutter `ChoiceChip`(Material3 기본 체크마크·
/// 보더) 대신 써서 앱 전체 필 스타일을 하나로 통일한다.
class PillOption extends StatelessWidget {
  const PillOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.inputBackground,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.white : AppColors.tertiaryText,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.tertiaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
