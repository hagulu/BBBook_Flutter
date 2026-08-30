import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import 'record_section_card.dart';

/// `ReadingStatusTile`(책 기록 상세)과 같은 구성 — 원형 아이콘 배지 + 라벨 —
/// 을 카드(`RecordSectionCard`)에 가로로 담아 진입 버튼으로 쓴다.
class EntryButton extends StatelessWidget {
  const EntryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 진입 대상 콘텐츠 개수 배지. null이면 표시하지 않는다(0은 배지로 표시).
  final int? count;

  @override
  Widget build(BuildContext context) {
    return RecordSectionCard(
      padding: EdgeInsets.zero,
      // RecordSectionCard의 불투명 Container가 InkWell과 그 잉크를 그리는
      // 조상 Material 사이에 끼어 있으면 스플래시가 카드 배경 뒤에 가려진다.
      // 카드 장식 위(=하위)에 투명 Material을 둬서 잉크가 그 위에 그려지게 한다.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.accentSurface.withValues(
                    alpha: 0.35,
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.accentForeground,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textStrong,
                    ),
                  ),
                ),
                if (count != null) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
                const Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 18,
                  color: AppColors.controlInactive,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
