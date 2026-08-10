import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'record_section_card.dart';

/// 독서 기간(탭하면 날짜 선택) + 출처/난이도/알게 된 경로(탭하면 팝업) 요약 카드.
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
    required this.onTapSource,
    required this.difficultyValue,
    required this.onTapDifficulty,
    required this.discoverySourceValue,
    required this.onTapDiscoverySource,
  });

  final DateTime? startedAt;
  final VoidCallback onTapStartedAt;
  final DateTime? finishedAt;
  final VoidCallback onTapFinishedAt;
  final String sourceValue;
  final VoidCallback onTapSource;
  final String difficultyValue;
  final VoidCallback onTapDifficulty;
  final String discoverySourceValue;
  final VoidCallback onTapDiscoverySource;

  @override
  Widget build(BuildContext context) {
    return RecordSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('독서 기간', icon: Icons.calendar_today_outlined),
          const SizedBox(height: 8),
          Row(
            children: [
              _DateValue(date: startedAt, onTap: onTapStartedAt),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: AppColors.mutedIcon,
                ),
              ),
              _DateValue(date: finishedAt, onTap: onTapFinishedAt),
            ],
          ),
          const Divider(height: 24, color: AppColors.border),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Tappable(
                  icon: Icons.style_outlined,
                  label: '출처',
                  value: sourceValue,
                  onTap: onTapSource,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: AppColors.border,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              Expanded(
                child: _Tappable(
                  icon: Icons.speed_outlined,
                  label: '난이도',
                  value: difficultyValue,
                  onTap: onTapDifficulty,
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: AppColors.border),
          _Tappable(
            icon: Icons.explore_outlined,
            label: '알게 된 경로',
            value: discoverySourceValue,
            onTap: onTapDiscoverySource,
          ),
        ],
      ),
    );
  }
}

class _DateValue extends StatelessWidget {
  const _DateValue({required this.date, required this.onTap});

  final DateTime? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(
          _formatDate(date),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: date == null ? AppColors.tertiaryText : AppColors.titleText,
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '년.월.일';
    return '${date.year}.${date.month}.${date.day}';
  }
}

class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
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
              const Spacer(),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.mutedIcon,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.titleText,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
