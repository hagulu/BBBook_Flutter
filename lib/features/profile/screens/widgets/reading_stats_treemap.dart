import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/reading_stats_summary.dart';

/// Finviz 시장 맵처럼 항목의 값을 면적으로 표현하는 독서 리포트용
/// squarified treemap. 외부 차트 라이브러리에 의존하지 않는다.
class ReadingStatsTreemap extends StatefulWidget {
  const ReadingStatsTreemap({super.key, required this.categories});

  final List<ReadingStatsCategory> categories;

  @override
  State<ReadingStatsTreemap> createState() => _ReadingStatsTreemapState();
}

class _ReadingStatsTreemapState extends State<ReadingStatsTreemap> {
  int? _selectedCategoryId;

  @override
  void didUpdateWidget(covariant ReadingStatsTreemap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedCategoryId == null) return;

    final stillExists = widget.categories.any(
      (category) => category.categoryId == _selectedCategoryId,
    );
    if (!stillExists) _selectedCategoryId = null;
  }

  void _handleTap(Offset position, List<_TreemapTile> tiles) {
    _TreemapTile? tappedTile;
    for (final tile in tiles) {
      if (tile.rect.contains(position)) {
        tappedTile = tile;
        break;
      }
    }

    setState(() {
      final tappedId = tappedTile?.category.categoryId;
      _selectedCategoryId = tappedId == _selectedCategoryId ? null : tappedId;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final tiles = _SquarifiedTreemapLayout.compute(widget.categories, size);
        ReadingStatsCategory? selectedCategory;
        _TreemapTile? selectedTile;
        for (final tile in tiles) {
          if (tile.category.categoryId == _selectedCategoryId) {
            selectedCategory = tile.category;
            selectedTile = tile;
            break;
          }
        }

        return Semantics(
          container: true,
          label: _semanticsLabel(widget.categories),
          excludeSemantics: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _handleTap(details.localPosition, tiles),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ReadingStatsTreemapPainter(
                          tiles: tiles,
                          selectedCategoryId: _selectedCategoryId,
                          textScaler: MediaQuery.textScalerOf(context),
                        ),
                      ),
                    ),
                    if (selectedCategory != null && selectedTile != null)
                      _TreemapTooltip(
                        category: selectedCategory,
                        tileRect: selectedTile.rect,
                        chartSize: size,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TreemapTooltip extends StatelessWidget {
  const _TreemapTooltip({
    required this.category,
    required this.tileRect,
    required this.chartSize,
  });

  static const _width = 190.0;
  static const _height = 42.0;

  final ReadingStatsCategory category;
  final Rect tileRect;
  final Size chartSize;

  @override
  Widget build(BuildContext context) {
    final width = math.min(_width, chartSize.width - 16);
    final left = (tileRect.center.dx - width / 2)
        .clamp(8.0, math.max(8.0, chartSize.width - width - 8))
        .toDouble();
    final preferredTop = tileRect.center.dy < chartSize.height / 2
        ? tileRect.bottom + 6
        : tileRect.top - _height - 6;
    final top = preferredTop
        .clamp(8.0, math.max(8.0, chartSize.height - _height - 8))
        .toDouble();
    final percent = (category.ratio * 100).round();

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: _height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.textStrong,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.surface),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowStrong,
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: category.color,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox.square(dimension: 8),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    category.categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.surface,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$percent% · ${category.count}권',
                  style: const TextStyle(
                    color: AppColors.surface,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadingStatsTreemapPainter extends CustomPainter {
  const _ReadingStatsTreemapPainter({
    required this.tiles,
    required this.selectedCategoryId,
    required this.textScaler,
  });

  static const _tileInset = 1.25;
  static const _labelPadding = 6.0;

  final List<_TreemapTile> tiles;
  final int? selectedCategoryId;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    for (final tile in tiles) {
      final rect = tile.rect.deflate(_tileInset);
      if (rect.width <= 0 || rect.height <= 0) continue;

      final shadedColor = Color.alphaBlend(
        AppColors.shadowSoft,
        tile.category.color,
      );
      final fill = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tile.category.color, shadedColor],
        ).createShader(rect);
      canvas.drawRect(rect, fill);

      if (tile.category.categoryId == selectedCategoryId) {
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = AppColors.surface,
        );
      }

      _paintLabel(canvas, rect, tile.category);
    }
  }

  void _paintLabel(
    Canvas canvas,
    Rect tileRect,
    ReadingStatsCategory category,
  ) {
    final contentRect = tileRect.deflate(_labelPadding);
    if (contentRect.width < 34 || contentRect.height < 20) return;

    final foreground = category.color.computeLuminance() > 0.48
        ? AppColors.textStrong
        : AppColors.surface;
    final showDetails = contentRect.width >= 58 && contentRect.height >= 38;
    final areaBasedSize =
        math.sqrt(contentRect.width * contentRect.height) * .15;
    var fontSize = areaBasedSize.clamp(10.0, 18.0).toDouble();
    TextPainter? labelPainter;

    while (fontSize >= 9) {
      final painter = TextPainter(
        text: TextSpan(
          style: TextStyle(
            color: foreground,
            fontSize: fontSize,
            height: 1.05,
            fontWeight: FontWeight.w800,
            shadows: foreground == AppColors.surface
                ? const [Shadow(color: AppColors.shadowStrong, blurRadius: 3)]
                : null,
          ),
          children: [
            TextSpan(text: category.categoryName),
            if (showDetails)
              TextSpan(
                text:
                    '\n${(category.ratio * 100).round()}% · ${category.count}권',
                style: TextStyle(
                  fontSize: fontSize * .7,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: showDetails ? 2 : 1,
        ellipsis: '…',
      )..layout(maxWidth: contentRect.width);

      if ((painter.height <= contentRect.height &&
              !painter.didExceedMaxLines) ||
          fontSize == 9) {
        labelPainter = painter;
        break;
      }
      fontSize = math.max(9, fontSize - 1);
    }

    if (labelPainter == null || labelPainter.height > contentRect.height) {
      return;
    }
    labelPainter.paint(
      canvas,
      Offset(
        contentRect.left + (contentRect.width - labelPainter.width) / 2,
        contentRect.top + (contentRect.height - labelPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _ReadingStatsTreemapPainter oldDelegate) =>
      oldDelegate.tiles != tiles ||
      oldDelegate.selectedCategoryId != selectedCategoryId ||
      oldDelegate.textScaler != textScaler;
}

class _SquarifiedTreemapLayout {
  const _SquarifiedTreemapLayout._();

  static List<_TreemapTile> compute(
    List<ReadingStatsCategory> categories,
    Size size,
  ) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      return const [];
    }

    final sorted = categories.where((category) => category.count > 0).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final total = sorted.fold<double>(
      0,
      (sum, category) => sum + category.count,
    );
    if (total <= 0) return const [];

    final bounds = Offset.zero & size;
    final entries = [
      for (final category in sorted)
        _TreemapEntry(
          category: category,
          area: category.count / total * bounds.width * bounds.height,
        ),
    ];
    final tiles = <_TreemapTile>[];
    final row = <_TreemapEntry>[];
    var remainingBounds = bounds;
    var entryIndex = 0;

    while (entryIndex < entries.length) {
      final entry = entries[entryIndex];
      final shortestSide = math.min(
        remainingBounds.width,
        remainingBounds.height,
      );
      if (row.isEmpty ||
          _worstAspectRatio([...row, entry], shortestSide) <=
              _worstAspectRatio(row, shortestSide)) {
        row.add(entry);
        entryIndex++;
      } else {
        remainingBounds = _layoutRow(row, remainingBounds, tiles);
        row.clear();
      }
    }

    if (row.isNotEmpty) _layoutRow(row, remainingBounds, tiles);
    return tiles;
  }

  static double _worstAspectRatio(List<_TreemapEntry> row, double side) {
    if (row.isEmpty || side <= 0) return double.infinity;

    final sum = row.fold<double>(0, (total, entry) => total + entry.area);
    final maxArea = row.fold<double>(0, (max, entry) {
      return math.max(max, entry.area);
    });
    final minArea = row.fold<double>(double.infinity, (min, entry) {
      return math.min(min, entry.area);
    });
    if (sum <= 0 || minArea <= 0) return double.infinity;

    final sideSquared = side * side;
    final sumSquared = sum * sum;
    return math.max(
      sideSquared * maxArea / sumSquared,
      sumSquared / (sideSquared * minArea),
    );
  }

  static Rect _layoutRow(
    List<_TreemapEntry> row,
    Rect bounds,
    List<_TreemapTile> tiles,
  ) {
    final rowArea = row.fold<double>(0, (total, entry) => total + entry.area);
    if (rowArea <= 0 || bounds.isEmpty) return bounds;

    if (bounds.width >= bounds.height) {
      final stripWidth = math.min(bounds.width, rowArea / bounds.height);
      var top = bounds.top;
      for (var index = 0; index < row.length; index++) {
        final height = index == row.length - 1
            ? bounds.bottom - top
            : row[index].area / stripWidth;
        tiles.add(
          _TreemapTile(
            category: row[index].category,
            rect: Rect.fromLTWH(bounds.left, top, stripWidth, height),
          ),
        );
        top += height;
      }
      return Rect.fromLTRB(
        bounds.left + stripWidth,
        bounds.top,
        bounds.right,
        bounds.bottom,
      );
    }

    final stripHeight = math.min(bounds.height, rowArea / bounds.width);
    var left = bounds.left;
    for (var index = 0; index < row.length; index++) {
      final width = index == row.length - 1
          ? bounds.right - left
          : row[index].area / stripHeight;
      tiles.add(
        _TreemapTile(
          category: row[index].category,
          rect: Rect.fromLTWH(left, bounds.top, width, stripHeight),
        ),
      );
      left += width;
    }
    return Rect.fromLTRB(
      bounds.left,
      bounds.top + stripHeight,
      bounds.right,
      bounds.bottom,
    );
  }
}

class _TreemapEntry {
  const _TreemapEntry({required this.category, required this.area});

  final ReadingStatsCategory category;
  final double area;
}

class _TreemapTile {
  const _TreemapTile({required this.category, required this.rect});

  final ReadingStatsCategory category;
  final Rect rect;
}

String _semanticsLabel(List<ReadingStatsCategory> categories) {
  final items = categories
      .map((category) {
        final percent = (category.ratio * 100).round();
        return '${category.categoryName} $percent%, ${category.count}권';
      })
      .join(', ');
  return '장르별 완독 비율 트리맵. $items';
}
