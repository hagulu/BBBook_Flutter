import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart' as fl;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/reading_stats_summary.dart';

/// 월별 완독 권수를 1~12월 선그래프로 표시한다. 왼쪽 Y축에는 데이터 범위에
/// 맞춘 권수 기준 눈금을 표시한다. 터치한 월의 툴팁은 다른 월을 선택할
/// 때까지 유지한다.
class ReadingStatsMonthlyChart extends StatefulWidget {
  const ReadingStatsMonthlyChart({super.key, required this.monthlyStats});

  final List<ReadingStatsMonthly> monthlyStats;

  @override
  State<ReadingStatsMonthlyChart> createState() =>
      _ReadingStatsMonthlyChartState();
}

class _ReadingStatsMonthlyChartState extends State<ReadingStatsMonthlyChart> {
  int? _selectedMonth;

  @override
  void didUpdateWidget(covariant ReadingStatsMonthlyChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedMonth == null) return;

    final stillExists = widget.monthlyStats.any(
      (stat) => stat.month == _selectedMonth,
    );
    if (!stillExists) _selectedMonth = null;
  }

  void _handleTouch(fl.FlTouchEvent event, fl.LineTouchResponse? response) {
    if (event is! fl.FlTapUpEvent) return;
    final touchedSpots = response?.lineBarSpots;
    if (touchedSpots == null || touchedSpots.isEmpty) return;

    final month = touchedSpots.first.x.round();
    if (month == _selectedMonth) return;
    setState(() => _selectedMonth = month);
  }

  @override
  Widget build(BuildContext context) {
    final monthlyStats = widget.monthlyStats;
    final maxCount = monthlyStats.fold<int>(
      0,
      (max, stat) => stat.count > max ? stat.count : max,
    );
    final interval = _axisInterval(maxCount);
    final maxY = maxCount == 0
        ? 4.0
        : ((maxCount + interval * 0.5) / interval).ceil() * interval;
    final spots = [
      for (final stat in monthlyStats)
        fl.FlSpot(stat.month.toDouble(), stat.count.toDouble()),
    ];
    final selectedSpotIndex = _selectedMonth == null
        ? -1
        : monthlyStats.indexWhere((stat) => stat.month == _selectedMonth);
    final lineBarData = fl.LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2,
      preventCurveOverShooting: true,
      color: AppColors.progressFill,
      barWidth: 3,
      isStrokeCapRound: true,
      isStrokeJoinRound: true,
      showingIndicators: selectedSpotIndex < 0 ? const [] : [selectedSpotIndex],
      belowBarData: fl.BarAreaData(show: true, color: AppColors.accentSurface),
      dotData: fl.FlDotData(
        getDotPainter: (spot, percent, barData, index) => fl.FlDotCirclePainter(
          radius: 3,
          color: AppColors.surface,
          strokeWidth: 2,
          strokeColor: AppColors.progressFill,
        ),
      ),
    );

    return Semantics(
      container: true,
      label: _semanticsLabel(monthlyStats),
      excludeSemantics: true,
      child: SizedBox(
        height: 190,
        child: fl.LineChart(
          fl.LineChartData(
            minX: 1,
            maxX: 12,
            minY: 0,
            maxY: maxY,
            showingTooltipIndicators: selectedSpotIndex < 0
                ? const []
                : [
                    fl.ShowingTooltipIndicators([
                      fl.LineBarSpot(lineBarData, 0, spots[selectedSpotIndex]),
                    ]),
                  ],
            gridData: fl.FlGridData(
              drawVerticalLine: false,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (_) => const fl.FlLine(
                color: AppColors.border,
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ),
            borderData: fl.FlBorderData(
              show: true,
              border: const Border(
                left: BorderSide(color: AppColors.border),
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            titlesData: fl.FlTitlesData(
              topTitles: const fl.AxisTitles(),
              rightTitles: const fl.AxisTitles(),
              leftTitles: fl.AxisTitles(
                sideTitles: fl.SideTitles(
                  showTitles: true,
                  interval: interval,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) => fl.SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(
                      '${value.toInt()}권',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
              bottomTitles: fl.AxisTitles(
                sideTitles: fl.SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 26,
                  getTitlesWidget: (value, meta) {
                    if (value < 1 ||
                        value > 12 ||
                        value != value.roundToDouble()) {
                      return const SizedBox.shrink();
                    }
                    return fl.SideTitleWidget(
                      meta: meta,
                      space: 6,
                      child: Text(
                        '${value.toInt()}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: fl.LineTouchData(
              handleBuiltInTouches: false,
              touchCallback: _handleTouch,
              touchTooltipData: fl.LineTouchTooltipData(
                getTooltipColor: (_) => AppColors.textStrong,
                tooltipBorderRadius: BorderRadius.circular(8),
                tooltipBorder: const BorderSide(color: AppColors.surface),
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                tooltipMargin: 10,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) => [
                  for (final spot in spots)
                    fl.LineTooltipItem(
                      '${spot.x.toInt()}월 · ${spot.y.toInt()}권',
                      const TextStyle(
                        color: AppColors.surface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              getTouchedSpotIndicator: (barData, spotIndexes) => [
                for (final _ in spotIndexes)
                  fl.TouchedSpotIndicatorData(
                    const fl.FlLine(
                      color: AppColors.accentForeground,
                      strokeWidth: 1,
                    ),
                    fl.FlDotData(
                      getDotPainter: (spot, percent, barData, index) =>
                          fl.FlDotCirclePainter(
                            radius: 5,
                            color: AppColors.surface,
                            strokeWidth: 2,
                            strokeColor: AppColors.progressFill,
                          ),
                    ),
                  ),
              ],
            ),
            lineBarsData: [lineBarData],
          ),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }
}

double _axisInterval(int maxCount) {
  if (maxCount <= 5) return 1;

  final roughInterval = maxCount / 5;
  final magnitude = math
      .pow(10, (math.log(roughInterval) / math.ln10).floor())
      .toDouble();
  final normalized = roughInterval / magnitude;
  final multiplier = normalized <= 1
      ? 1
      : normalized <= 2
      ? 2
      : normalized <= 5
      ? 5
      : 10;
  return multiplier * magnitude;
}

String _semanticsLabel(List<ReadingStatsMonthly> monthlyStats) {
  final values = monthlyStats
      .map((stat) => '${stat.month}월 ${stat.count}권')
      .join(', ');
  return '월별 완독 선그래프. $values';
}
