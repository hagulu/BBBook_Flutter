import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

final _kHexColorPattern = RegExp(
  r'^#(?:[0-9a-f]{3}|[0-9a-f]{6})$',
  caseSensitive: false,
);

/// 독서 통계(리포트) 화면의 카테고리별 통계(`stats-screen.md` §1-4).
/// 서버 API(`api-me-reading-stats-summary-get.md`) 대신 로컬 서재 데이터로
/// 계산한다(`reading_stats_calculator.dart` 참고).
class ReadingStatsCategory {
  const ReadingStatsCategory({
    required this.categoryId,
    required this.categoryName,
    required this.colorHex,
    required this.count,
    required this.ratio,
  });

  final int categoryId;
  final String categoryName;
  final String colorHex;
  final int count;
  final double ratio;

  /// [colorHex]가 유효한 HEX 문자열이 아니면(카테고리 마스터 캐시에 없는
  /// 경우 포함) 회색([AppColors.border])으로 대체한다(`stats-screen.md`
  /// §1-4).
  Color get color {
    if (!_kHexColorPattern.hasMatch(colorHex)) return AppColors.border;
    final normalized = colorHex.replaceFirst('#', '');
    final expanded = normalized.length == 3
        ? normalized.split('').map((c) => '$c$c').join()
        : normalized;
    return Color(int.parse('FF$expanded', radix: 16));
  }
}

/// 독서 통계(리포트) 화면의 월별 완독 통계(`stats-screen.md` §1-5).
class ReadingStatsMonthly {
  const ReadingStatsMonthly({required this.month, required this.count});

  final int month;
  final int count;
}

/// 독서 통계(리포트) 화면 요약 데이터(`stats-screen.md` §1-3~§1-6). 서버
/// API(`api-me-reading-stats-summary-get.md`) 대신 로컬 서재·노트 데이터로
/// 계산한다(`reading_stats_calculator.dart`, `reading_stats_providers.dart`
/// 참고).
class ReadingStatsSummary {
  const ReadingStatsSummary({
    required this.finishedCount,
    required this.totalPages,
    required this.noteMemoCount,
    required this.categoryStats,
    this.monthlyYear,
    required this.monthlyStats,
    required this.rereadCount,
    required this.masterpieceCount,
    required this.averageRating,
    required this.mostReadPublisher,
  });

  final int finishedCount;
  final int totalPages;
  final int noteMemoCount;
  final List<ReadingStatsCategory> categoryStats;

  /// 월별 완독 통계 기준 연도. null이면 전체 기간을 월 단위로 합산한
  /// 것이다(연도를 지정하면 그 해로 좁힌다).
  final int? monthlyYear;
  final List<ReadingStatsMonthly> monthlyStats;
  final int rereadCount;
  final int masterpieceCount;
  final double? averageRating;

  /// 더 보기 섹션 표시 후보였으나 현재 화면에는 표시하지 않는다(임시 —
  /// `reading_stats_screen.dart`의 `_moreItems` 참고). 데이터 자체는 계속
  /// 계산해 둔다.
  final String? mostReadPublisher;
}
