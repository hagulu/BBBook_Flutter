import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'record_field_tile.dart';
import 'record_section_card.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 독서 기간(탭하면 날짜 선택) + 출처/난이도(탭하면 팝업) 요약 카드.
/// `book-record.md` 스크린샷의 "독서 기간 / 출처 / 난이도" 3열 카드를
/// 모바일 폭에 맞춰 재배치했다.
class MetaSummaryCard extends StatelessWidget {
  const MetaSummaryCard({
    super.key,
    required this.startedAt,
    required this.onTapStartedAt,
    required this.finishedAt,
    required this.onTapFinishedAt,
    required this.sourceValue,
    required this.sourceHasValue,
    required this.onTapSource,
    this.sourceIcon,
    required this.difficultyValue,
    required this.difficultyHasValue,
    required this.onTapDifficulty,
    this.difficultyIcon,
  });

  final DateTime? startedAt;
  final VoidCallback onTapStartedAt;
  final DateTime? finishedAt;
  final VoidCallback onTapFinishedAt;
  final String sourceValue;
  final bool sourceHasValue;
  final VoidCallback onTapSource;
  final IconData? sourceIcon;
  final String difficultyValue;
  final bool difficultyHasValue;
  final VoidCallback onTapDifficulty;
  final IconData? difficultyIcon;

  @override
  Widget build(BuildContext context) {
    return RecordSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('독서 기간', icon: PhosphorIconsRegular.calendar),
          const SizedBox(height: 8),
          Row(
            children: [
              _DateValue(label: '시작일', date: startedAt, onTap: onTapStartedAt),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  PhosphorIconsRegular.arrowRight,
                  size: 14,
                  color: AppColors.mutedIcon,
                ),
              ),
              _DateValue(
                label: '완독일',
                date: finishedAt,
                onTap: onTapFinishedAt,
              ),
            ],
          ),
          const Divider(height: 24, color: AppColors.border),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RecordFieldTile(
                  label: '출처',
                  value: sourceValue,
                  hasValue: sourceHasValue,
                  onTap: onTapSource,
                  valueIcon: sourceIcon,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: AppColors.border,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              Expanded(
                child: RecordFieldTile(
                  label: '난이도',
                  value: difficultyValue,
                  hasValue: difficultyHasValue,
                  onTap: onTapDifficulty,
                  valueIcon: difficultyIcon,
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
          constraints: const BoxConstraints(minHeight: 36),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Text(
            currentDate == null ? label : _formatDate(currentDate),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: currentDate == null
                  ? AppColors.tertiaryText
                  : AppColors.titleText,
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
