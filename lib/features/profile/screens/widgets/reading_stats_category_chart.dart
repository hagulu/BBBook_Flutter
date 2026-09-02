import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/reading_stats_summary.dart';
import 'reading_stats_treemap.dart';

/// 장르별 완독 비율을 트리맵으로 표시하고 숫자 상세를 토글한다.
class ReadingStatsCategoryChart extends StatefulWidget {
  const ReadingStatsCategoryChart({super.key, required this.categories});

  final List<ReadingStatsCategory> categories;

  @override
  State<ReadingStatsCategoryChart> createState() =>
      _ReadingStatsCategoryChartState();
}

class _ReadingStatsCategoryChartState extends State<ReadingStatsCategoryChart> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: ReadingStatsTreemap(categories: categories),
        ),
        const SizedBox(height: 8),
        Align(
          child: TextButton(
            onPressed: () => setState(() => _showDetails = !_showDetails),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentForeground,
              minimumSize: const Size(96, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Text(
                    _showDetails ? '접기' : '자세히',
                    key: ValueKey(_showDetails),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _showDetails ? .5 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: const Icon(PhosphorIconsRegular.caretDown, size: 16),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _showDetails
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    _CategoryDetails(categories: categories),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _CategoryDetails extends StatelessWidget {
  const _CategoryDetails({required this.categories});

  final List<ReadingStatsCategory> categories;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: _detailsSemanticsLabel(categories),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            for (final category in categories)
              _CategoryDetailRow(category: category),
          ],
        ),
      ),
    );
  }
}

class _CategoryDetailRow extends StatelessWidget {
  const _CategoryDetailRow({required this.category});

  final ReadingStatsCategory category;

  @override
  Widget build(BuildContext context) {
    final percent = (category.ratio * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: category.color,
              borderRadius: BorderRadius.circular(2),
            ),
            child: const SizedBox.square(dimension: 10),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * .65,
                      ),
                      child: Text(
                        category.categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textBody,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: SizedBox(
                        height: 2,
                        child: CustomPaint(painter: _DottedLeaderPainter()),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48),
            child: Text(
              '$percent%',
              maxLines: 1,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textStrong,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48),
            child: Text(
              '${category.count}권',
              maxLines: 1,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textBody,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DottedLeaderPainter extends CustomPainter {
  const _DottedLeaderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: .55)
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;
    const dashLength = 2.0;
    const gapLength = 3.0;
    final centerY = size.height / 2;

    for (var x = 0.0; x < size.width; x += dashLength + gapLength) {
      canvas.drawLine(
        Offset(x, centerY),
        Offset(math.min(x + dashLength, size.width), centerY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLeaderPainter oldDelegate) => false;
}

String _detailsSemanticsLabel(List<ReadingStatsCategory> categories) {
  final items = categories
      .map((category) {
        final percent = (category.ratio * 100).round();
        return '${category.categoryName} $percent%, ${category.count}권';
      })
      .join(', ');
  return '장르별 완독 숫자 상세. $items';
}
