import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 라벨(위) / 아이콘+값(아래)로 구성된 탭 가능한 필드. 출처·난이도·독서 상태·
/// 알게 된 경로처럼 "현재 값을 보여주고 탭하면 팝업으로 바꾸는" 필드가
/// 공유하는 모양이다. [hasValue]가 false면 값이 아직 설정되지 않은
/// 플레이스홀더 문구라는 뜻으로, 작고 옅은 색으로 구분해 보여준다.
///
/// [valueIcon]은 라벨 고정 아이콘이 아니라 "현재 선택된 값"에 대응하는
/// 아이콘이다(예: 출처="전자책"이면 태블릿 아이콘). 값에 대응하는 아이콘이
/// 없는 필드(자유 텍스트인 "알게 된 경로" 등)는 null로 두면 아이콘 없이
/// 값만 표시된다 — 없는 아이콘을 억지로 채우지 않는다.
class RecordFieldTile extends StatelessWidget {
  const RecordFieldTile({
    super.key,
    required this.label,
    required this.value,
    required this.hasValue,
    required this.onTap,
    this.valueIcon,
  });

  final String label;
  final String value;
  final bool hasValue;
  final VoidCallback onTap;
  final IconData? valueIcon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.titleText,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            // 아이콘이 붙는 값(출처/난이도)은 짧은 고정 라벨이라 항상 한 줄이라
            // 세로 중앙 정렬이 더 자연스럽다(아이콘 없는 자유 텍스트만 2줄까지
            // 늘어날 수 있는데, 그 경우엔 애초에 아이콘이 없다).
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasValue && valueIcon != null) ...[
                Icon(valueIcon, size: 15, color: AppColors.primary),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: hasValue ? 15 : 13,
                    fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
                    color: hasValue
                        ? AppColors.titleText
                        : AppColors.mutedIcon,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
