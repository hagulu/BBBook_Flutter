import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_loading.dart';
import '../models/reading_stats_summary.dart';
import '../providers/reading_stats_providers.dart';
import 'widgets/reading_stats_category_chart.dart';
import 'widgets/reading_stats_monthly_chart.dart';
import 'widgets/reading_stats_year_picker.dart';

/// 독서 통계(리포트) 화면(`docs/porting-reference/stats-screen.md`).
///
/// 전역 헤더는 뒤로가기 아이콘만 표시하고(§1-1), 화면 본문의 "독서 리포트"
/// 텍스트가 실질적인 타이틀 역할을 한다.
class ReadingStatsScreen extends ConsumerStatefulWidget {
  const ReadingStatsScreen({super.key});

  @override
  ConsumerState<ReadingStatsScreen> createState() => _ReadingStatsScreenState();
}

class _ReadingStatsScreenState extends ConsumerState<ReadingStatsScreen> {
  int? _selectedYear;

  @override
  Widget build(BuildContext context) {
    final years = ref.watch(readingStatsYearsProvider).valueOrNull ?? const [];
    final summaryAsync = ref.watch(readingStatsSummaryProvider(_selectedYear));

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '독서 리포트',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textStrong,
                    ),
                  ),
                  ReadingStatsYearPicker(
                    years: years,
                    selectedYear: _selectedYear,
                    onChanged: (year) => setState(() => _selectedYear = year),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 이전 값이 있는데 동일 연도로 다시 로딩 중이면(백그라운드
              // 동기화로 인한 재조회 등, `bookshelfSyncVersionProvider` 참고)
              // 전체를 "불러오는 중..."으로 덮어쓰지 않고 공통
              // [AppLoadingOverlay]만 얹는다(`book_detail_screen.dart`와 같은
              // 관례). 값이 아직 없으면(최초 진입, 연도 전환 직후) 텍스트
              // 로딩 상태를 보여준다.
              if (summaryAsync.hasValue)
                AppLoadingOverlay(
                  isLoading: summaryAsync.isLoading,
                  child: _StatsContent(
                    stats: summaryAsync.value!,
                    selectedYear: _selectedYear,
                  ),
                )
              else if (summaryAsync.hasError)
                _ErrorState(
                  onRetry: () => ref.invalidate(
                    readingStatsSummaryProvider(_selectedYear),
                  ),
                )
              else
                const _LoadingState(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: Text('불러오는 중...', style: TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '불러오기에 실패했습니다',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

class _StatsContent extends StatelessWidget {
  const _StatsContent({required this.stats, required this.selectedYear});

  final ReadingStatsSummary stats;
  final int? selectedYear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('요약'),
        const SizedBox(height: 10),
        _SummaryCards(stats: stats),
        if (stats.categoryStats.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _SectionLabel('카테고리'),
          const SizedBox(height: 10),
          _Card(
            child: ReadingStatsCategoryChart(categories: stats.categoryStats),
          ),
        ],
        const SizedBox(height: 20),
        _SectionLabel(
          '월별 완독 · ${stats.monthlyYear == null ? '전체' : '${stats.monthlyYear}년'}',
        ),
        const SizedBox(height: 10),
        _Card(
          child: ReadingStatsMonthlyChart(monthlyStats: stats.monthlyStats),
        ),
        if (_moreItems(stats).isNotEmpty) ...[
          const SizedBox(height: 20),
          const _SectionLabel('더 보기'),
          const SizedBox(height: 10),
          _MoreSection(items: _moreItems(stats)),
        ],
        if (stats.finishedCount == 0) ...[
          const SizedBox(height: 32),
          _EmptyState(selectedYear: selectedYear),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.stats});

  final ReadingStatsSummary stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: PhosphorIconsRegular.bookOpen,
            value: _formatThousands(stats.finishedCount),
            unit: '권',
            label: '완독 권수',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            icon: PhosphorIconsRegular.stack,
            value: _formatThousands(stats.totalPages),
            unit: 'p',
            label: '읽은 페이지',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            icon: PhosphorIconsRegular.fileText,
            value: _formatThousands(stats.noteMemoCount),
            unit: '개',
            label: '메모',
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.accentForeground),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// "많이 읽은 출판사"는 일단 표시에서 제외한다(요청에 따른 임시 제거 —
// 데이터 자체는 [ReadingStatsSummary.mostReadPublisher]에 그대로 남아 있다).
List<_MoreItem> _moreItems(ReadingStatsSummary stats) {
  return [
    if (stats.rereadCount > 0)
      _MoreItem(value: '${stats.rereadCount}회', label: '재독 횟수'),
    if (stats.masterpieceCount > 0)
      _MoreItem(value: '${stats.masterpieceCount}권', label: '인생책'),
    if (stats.averageRating != null)
      _MoreItem(
        value: '★ ${stats.averageRating!.toStringAsFixed(1)}',
        label: '평균 평점',
      ),
  ];
}

class _MoreSection extends StatelessWidget {
  const _MoreSection({required this.items});

  final List<_MoreItem> items;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const VerticalDivider(width: 1, color: AppColors.border),
              Expanded(child: _MoreColumn(item: items[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem({required this.value, required this.label});

  final String value;
  final String label;
}

class _MoreColumn extends StatelessWidget {
  const _MoreColumn({required this.item});

  final _MoreItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          item.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textStrong,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.label,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.selectedYear});

  final int? selectedYear;

  @override
  Widget build(BuildContext context) {
    final year = selectedYear;
    final message = year == null ? '완독 기록이 없습니다' : '$year년의 독서 기록이 없습니다';
    return Center(
      child: Column(
        children: [
          const Text('📚', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

String _formatThousands(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}
