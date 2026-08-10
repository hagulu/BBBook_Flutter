import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 아이콘+라벨(위) / 값(아래)로 구성된 탭 가능한 필드. 출처·난이도·독서 상태·
/// 알게 된 경로처럼 "현재 값을 보여주고 탭하면 팝업으로 바꾸는" 필드가
/// 공유하는 모양이다. [hasValue]가 false면 값이 아직 설정되지 않은
/// 플레이스홀더 문구라는 뜻으로, 작고 옅은 색으로 구분해 보여준다.
class RecordFieldTile extends StatelessWidget {
  const RecordFieldTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.hasValue,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool hasValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.titleText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: hasValue ? 15 : 13,
              fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
              color: hasValue ? AppColors.titleText : AppColors.mutedIcon,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
