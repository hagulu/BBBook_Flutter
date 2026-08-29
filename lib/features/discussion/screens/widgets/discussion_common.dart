import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';

/// 닫힘/스포일러 등 상태 배지(pill).
class DiscussionBadge extends StatelessWidget {
  const DiscussionBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  /// 마감된 토론임을 알리는 배지.
  const DiscussionBadge.closed({Key? key})
    : this(
        key: key,
        icon: PhosphorIconsRegular.lock,
        label: '마감',
        foreground: AppColors.textMuted,
        background: AppColors.surfaceSubtle,
      );

  /// 스포일러가 포함된 글임을 알리는 배지.
  const DiscussionBadge.spoiler({Key? key})
    : this(
        key: key,
        icon: PhosphorIconsRegular.eyeSlash,
        label: '스포일러',
        foreground: AppColors.memoThoughtForeground,
        background: AppColors.highlightGoldSurface,
      );

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// "답변 N개"처럼 섹션을 구분하는 좌측 바 + 라벨.
class DiscussionSectionLabel extends StatelessWidget {
  const DiscussionSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.accentFill,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textStrong,
          ),
        ),
      ],
    );
  }
}
