import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'record_section_card.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 독서 기간(탭하면 날짜 선택) 카드. 완독일은 완독 상태에서만 의미가 있어
/// [showFinishedAt]이 false면 시작일만 보여준다(빈 칸을 남기지 않는다) —
/// 이때는 완독일과 나란히 대비될 때와 달리 "무슨 날짜인지"가 값만 봐서는
/// 드러나지 않아 앞에 "시작" 라벨을 붙인다.
class MetaSummaryCard extends StatelessWidget {
  const MetaSummaryCard({
    super.key,
    required this.startedAt,
    required this.onTapStartedAt,
    this.finishedAt,
    this.onTapFinishedAt,
    this.showFinishedAt = true,
  });

  final DateTime? startedAt;
  final VoidCallback onTapStartedAt;
  final DateTime? finishedAt;
  final VoidCallback? onTapFinishedAt;
  final bool showFinishedAt;

  @override
  Widget build(BuildContext context) {
    return RecordSectionCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('독서 기간', icon: PhosphorIconsRegular.calendar),
          const SizedBox(height: 6),
          if (showFinishedAt)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _DateValue(
                    label: '시작일',
                    date: startedAt,
                    onTap: onTapStartedAt,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Icon(
                    PhosphorIconsRegular.arrowRight,
                    size: 16,
                    color: AppColors.controlInactive,
                  ),
                ),
                Expanded(
                  child: _DateValue(
                    label: '완독일',
                    date: finishedAt,
                    onTap: onTapFinishedAt!,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                // 시작일이 아직 없으면 값 자리에 "시작일" 플레이스홀더가
                // 이미 무슨 날짜인지 말해주므로 "시작" 라벨은 값이 있을
                // 때만 붙인다(없으면 라벨+플레이스홀더가 중복돼 보인다).
                if (startedAt != null) ...[
                  const Text(
                    '시작',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _DateValue(
                    label: startedAt != null ? '날짜 선택' : '시작일',
                    date: startedAt,
                    onTap: onTapStartedAt,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DateValue extends StatelessWidget {
  const _DateValue({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final currentDate = date;
    return Semantics(
      button: true,
      label: currentDate == null
          ? label
          : '$label, ${_formatDate(currentDate)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: Text(
            currentDate == null ? label : _formatDate(currentDate),
            style: TextStyle(
              fontSize: currentDate == null ? 13 : 15,
              fontWeight: FontWeight.w600,
              color: currentDate == null
                  ? AppColors.textMuted
                  : AppColors.textStrong,
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.year}.${date.month}.${date.day}';
  }
}
