import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/reading_stats_summary.dart';

/// "월별 완독" 막대 차트(`stats-screen.md` §1-5). 원본은 마우스 호버로
/// "{count}권" 툴팁을 보여주지만 터치 환경에는 호버가 없으므로, 대신 막대를
/// 탭하면 그 위에 값을 토글해서 보여준다.
class ReadingStatsMonthlyChart extends StatefulWidget {
  const ReadingStatsMonthlyChart({super.key, required this.monthlyStats});

  final List<ReadingStatsMonthly> monthlyStats;

  @override
  State<ReadingStatsMonthlyChart> createState() =>
      _ReadingStatsMonthlyChartState();
}

class _ReadingStatsMonthlyChartState extends State<ReadingStatsMonthlyChart> {
  static const _maxBarHeight = 110.0;
  static const _minBarHeight = 2.0;

  int? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    final maxCount = widget.monthlyStats.fold<int>(
      0,
      (max, stat) => stat.count > max ? stat.count : max,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final stat in widget.monthlyStats)
          Expanded(
            child: _MonthBar(
              stat: stat,
              barHeight: maxCount == 0
                  ? _minBarHeight
                  : (stat.count / maxCount * _maxBarHeight).clamp(
                      _minBarHeight,
                      _maxBarHeight,
                    ),
              maxBarHeight: _maxBarHeight,
              showTooltip: _selectedMonth == stat.month,
              onTap: () => setState(() {
                _selectedMonth = _selectedMonth == stat.month
                    ? null
                    : stat.month;
              }),
            ),
          ),
      ],
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.stat,
    required this.barHeight,
    required this.maxBarHeight,
    required this.showTooltip,
    required this.onTap,
  });

  final ReadingStatsMonthly stat;
  final double barHeight;
  final double maxBarHeight;
  final bool showTooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${stat.month}월 ${stat.count}권',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 20,
              child: showTooltip
                  ? Align(
                      alignment: Alignment.bottomCenter,
                      child: Text(
                        '${stat.count}권',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textStrong,
                        ),
                      ),
                    )
                  : null,
            ),
            SizedBox(
              height: maxBarHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 12,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: stat.count > 0
                        ? AppColors.progressFill
                        : AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${stat.month}',
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
