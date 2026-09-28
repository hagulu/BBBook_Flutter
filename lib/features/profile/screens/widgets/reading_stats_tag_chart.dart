import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/reading_stats_summary.dart';

const _kDefaultVisibleCount = 5;

/// 태그별 완독 권수를 가로 막대 그래프로 표시한다. [tags]는 이미 개수
/// 내림차순으로 정렬돼 있다고 가정한다(`reading_stats_calculator.dart`).
/// 기본 5개만 보여주고, 5개를 초과하면 "더보기"로 전체를 펼친다.
class ReadingStatsTagChart extends StatefulWidget {
  const ReadingStatsTagChart({super.key, required this.tags});

  final List<ReadingStatsTag> tags;

  @override
  State<ReadingStatsTagChart> createState() => _ReadingStatsTagChartState();
}

class _ReadingStatsTagChartState extends State<ReadingStatsTagChart> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final tags = widget.tags;
    final maxCount = tags.isEmpty ? 0 : tags.first.count;
    final hasMore = tags.length > _kDefaultVisibleCount;

    final visibleTags = _showAll ? tags : tags.take(_kDefaultVisibleCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: _semanticsLabel(visibleTags),
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tag in tags.take(_kDefaultVisibleCount))
                _TagBarRow(tag: tag, maxCount: maxCount),
              if (hasMore)
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _showAll
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final tag in tags.skip(_kDefaultVisibleCount))
                              _TagBarRow(tag: tag, maxCount: maxCount),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
            ],
          ),
        ),
        if (hasMore) ...[
          const SizedBox(height: 4),
          Align(
            child: TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.of(context).accentForeground,
                minimumSize: const Size(96, 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Text(
                      _showAll ? '접기' : '더보기',
                      key: ValueKey(_showAll),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _showAll ? .5 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: const Icon(PhosphorIconsRegular.caretDown, size: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TagBarRow extends StatelessWidget {
  const _TagBarRow({required this.tag, required this.maxCount});

  final ReadingStatsTag tag;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final ratio = maxCount <= 0 ? 0.0 : (tag.count / maxCount).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tag.tagName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.of(context).textStrong,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${tag.count}권',
                maxLines: 1,
                style: TextStyle(
                  color: AppColors.of(context).textStrong,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.of(context).border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    height: 8,
                    width: constraints.maxWidth * ratio,
                    decoration: BoxDecoration(
                      color: AppColors.of(context).progressFill,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _semanticsLabel(Iterable<ReadingStatsTag> tags) {
  final items = tags
      .map((tag) => '${tag.tagName} ${tag.count}권')
      .join(', ');
  return '태그별 완독 가로 막대 그래프. $items';
}
