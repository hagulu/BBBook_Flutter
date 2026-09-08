/// 독서 통계(리포트) 화면(`docs/porting-reference/stats-screen.md`)은 서버
/// API(`api-me-books-statistics-years-get.md`,
/// `api-me-reading-stats-summary-get.md`) 대신 로컬 서재 데이터로 직접
/// 계산한다(`profile_providers.dart`의 `profileStatsSummaryProvider`와 동일한
/// 관례, 계산 자체는 `reading_stats_calculator.dart` 참고).
///
/// 완독 처리·쪽수/카테고리/노트 수정 등 로컬 DB 변경 후 재계산되도록
/// `bookshelfSyncVersionProvider`/`bookNoteSyncVersionProvider`를 구독한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_notifier.dart';
import '../../book_note/providers/book_note_providers.dart';
import '../../bookshelf/models/book_category.dart';
import '../../bookshelf/models/book_status.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../models/reading_stats_summary.dart';
import '../services/reading_stats_calculator.dart';

/// 연도 드롭다운 옵션(`stats-screen.md` §1-2). 완독 책이 없으면 빈 배열
/// (드롭다운에 "전체"만 남는다).
final readingStatsYearsProvider = FutureProvider.autoDispose<List<int>>((
  ref,
) async {
  ref.watch(bookshelfSyncVersionProvider);
  final finished = await ref
      .watch(bookshelfRepositoryProvider)
      .getGridTab(BookStatus.finished);
  return computeReadingStatsYears(finished);
});

/// 통계 요약 조회(`stats-screen.md` §1-3~§1-6). `year`가 null이면 전체
/// 기간이며, 월별 통계도 (원본 웹의 "현재 연도만" 예외 없이) 전 기간을
/// 월 단위로 합산한다 — 연도를 지정하면 그 해로만 좁힌다.
final readingStatsSummaryProvider = FutureProvider.autoDispose
    .family<ReadingStatsSummary, int?>((ref, year) async {
      ref.watch(bookshelfSyncVersionProvider);
      ref.watch(bookNoteSyncVersionProvider);

      final ownerUserId = ref.watch(
        authNotifierProvider.select((auth) => auth.user?.id),
      );

      final repository = ref.watch(bookshelfRepositoryProvider);
      final allFinished = await repository.getGridTab(BookStatus.finished);
      // 카테고리 마스터 캐시는 색상 조회용 보조 데이터일 뿐이라(카테고리별
      // 집계 자체는 책에 저장된 이름으로 이뤄진다 — `reading_stats_calculator.dart`
      // 참고) 조회에 실패해도(오프라인 등) 화면 전체를 에러로 빠뜨리지 않고
      // 빈 목록으로 대체한다.
      final categories = await repository.getCachedCategories().catchError(
        (_) => const <BookCategory>[],
      );

      final yearFiltered = year == null
          ? allFinished
          : allFinished.where((item) => item.finishedAt?.year == year).toList();

      // "전체" 선택 시(year == null) 월별 완독도 전 기간을 월 단위로
      // 합산한다 — 요약·카테고리 등 다른 통계와 같은 범위([yearFiltered])를
      // 그대로 쓰면 된다(원본 웹처럼 현재 연도로 좁히지 않는다, 사용자 요청).
      final monthlyFiltered = yearFiltered;

      final noteMemoCount = ownerUserId == null
          ? 0
          : await ref
                .watch(bookNoteDaoProvider)
                .countMemosForFinishedBooks(
                  ownerUserId: ownerUserId,
                  finishedStatusApiValue: BookStatus.finished.apiValue,
                  year: year,
                );

      return computeReadingStatsSummary(
        yearFiltered: yearFiltered,
        monthlyFiltered: monthlyFiltered,
        monthlyYear: year,
        categories: categories,
        noteMemoCount: noteMemoCount,
      );
    });
