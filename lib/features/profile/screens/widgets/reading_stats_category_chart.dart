import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/reading_stats_summary.dart';

/// "카테고리" 도넛 차트 + 범례(`stats-screen.md` §1-4). [categories]가
/// 비어 있으면 이 위젯을 아예 렌더링하지 않는 건 호출부(스크린)의 책임이다.
class ReadingStatsCategoryChart extends StatelessWidget {
  const ReadingStatsCategoryChart({super.key, required this.categories});

  final List<ReadingStatsCategory> categories;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: CustomPaint(painter: _DonutPainter(categories: categories)),
        ),
        const SizedBox(height: 16),
        _CategoryLegend(categories: categories),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.categories});

  final List<ReadingStatsCategory> categories;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final strokeWidth = radius * 0.42;
    final arcRadius = radius - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: arcRadius);
    final gap = categories.length > 1 ? 0.035 : 0.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    var startAngle = -math.pi / 2;
    for (final category in categories) {
      final sweep = category.ratio * 2 * math.pi;
      paint.color = category.color;
      // 매우 작은 조각(1권 미만 비율 등)은 고정 간격을 그대로 빼면 아예
      // 사라져버리므로, 간격의 2배보다 클 때만 틈을 둔다.
      final hasGap = sweep > gap * 2;
      canvas.drawArc(
        rect,
        startAngle + (hasGap ? gap / 2 : 0),
        hasGap ? sweep - gap : sweep,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.categories != categories;
}

class _CategoryLegend extends StatelessWidget {
  const _CategoryLegend({required this.categories});

  final List<ReadingStatsCategory> categories;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        const columns = 3;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 10,
          children: [
            for (final category in categories)
              SizedBox(
                width: itemWidth,
                child: _CategoryLegendItem(category: category),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryLegendItem extends StatelessWidget {
  const _CategoryLegendItem({required this.category});

  final ReadingStatsCategory category;

  @override
  Widget build(BuildContext context) {
    final percent = (category.ratio * 100).round();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: category.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, color: AppColors.textBody),
              children: [
                TextSpan(text: '${category.categoryName} '),
                TextSpan(
                  text: '$percent%',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' · ${category.count}권'),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
