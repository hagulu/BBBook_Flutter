import '../../bookshelf/models/book_category.dart';
import '../../bookshelf/models/book_item.dart';
import '../models/reading_stats_summary.dart';

/// [ReadingStatsScreen]이 서버 API(`api-me-reading-stats-summary-get.md`)
/// 대신 로컬 서재 데이터로 직접 계산하는 순수 함수
/// (`reading_stats_providers.dart`의 `readingStatsSummaryProvider` 참고).
/// 완독 기준은 `status = FINISHED`로, 연도 필터는 [BookItem.finishedAt]
/// 기준(문서 §4-2와 동일한 규칙).
///
/// - [yearFiltered]: 연도(또는 전체) 필터가 적용된 완독 책 목록. 요약·카테고리·
///   출판사 등 상단 통계 전부가 이 목록을 기준으로 계산된다.
/// - [monthlyFiltered]: 월별 완독 집계 전용 목록. "전체" 선택 시([monthlyYear]가
///   null)에는 [yearFiltered](전 기간)를 그대로 넘겨 월 단위로 합산한다.
/// - [categories]: 카테고리 이름·색상 조회용 마스터 캐시. 특정 ID가 없으면
///   책에 저장된 이전 이름으로 대체하고, 그마저 없는 책만 카테고리 집계에서
///   빠진다(아래 참고). 색상을 못 찾은 조각은 회색으로 표시된다.
/// - [noteMemoCount]: [yearFiltered]와 동일한 책 범위로 미리 조회해 둔 메모
///   개수(로컬 DB 비동기 조회라 호출부가 먼저 구해서 넘긴다).
ReadingStatsSummary computeReadingStatsSummary({
  required List<BookItem> yearFiltered,
  required List<BookItem> monthlyFiltered,
  required int? monthlyYear,
  required List<BookCategory> categories,
  required int noteMemoCount,
}) {
  final totalPages = yearFiltered.fold<int>(
    0,
    (sum, item) => sum + (item.statsTotalPages ?? 0),
  );

  // [BookItem.displayCategoryId](카테고리 ID)로 묶는다. 이름은 우선
  // 카테고리 마스터 캐시에서 찾고, 캐시에 없으면 책에 저장된 이전 이름
  // ([BookItem.category])으로 대체한다 — `book_record_repository.dart`의
  // `_updateBookInfoLocally`가 로컬 저장 모드에서 카테고리를 바꿀 때 ID만
  // 남기고 이름은 일부러 비워 두면서 "화면은 ID로 마스터 목록에서 이름을
  // 찾는다"고 명시한 것과 같은 관례다. 두 경로 모두 이름을 못 찾는
  // 책(ID는 있지만 마스터에도 없고 이전 이름도 없는 경우)만 집계에서 빠진다.
  final categoryIdCounts = <int, int>{};
  final categoryNameFallback = <int, String?>{};
  for (final item in yearFiltered) {
    final categoryId = item.displayCategoryId;
    if (categoryId == null) continue;
    categoryIdCounts[categoryId] = (categoryIdCounts[categoryId] ?? 0) + 1;
    categoryNameFallback.putIfAbsent(categoryId, () => item.category);
  }
  final categoryById = {
    for (final category in categories) category.id: category,
  };
  final resolvedCategories = [
    for (final entry in categoryIdCounts.entries)
      if ((categoryById[entry.key]?.name ?? categoryNameFallback[entry.key])
          case final name?)
        (
          categoryId: entry.key,
          categoryName: name,
          colorHex: categoryById[entry.key]?.colorHex,
          count: entry.value,
        ),
  ]..sort((a, b) => b.count.compareTo(a.count));
  final categoryTotal = resolvedCategories.fold<int>(
    0,
    (sum, entry) => sum + entry.count,
  );
  final categoryStats = [
    for (final entry in resolvedCategories)
      ReadingStatsCategory(
        categoryId: entry.categoryId,
        categoryName: entry.categoryName,
        // 마스터 캐시에 없으면 빈 문자열을 넘겨 [ReadingStatsCategory.color]의
        // 기존 HEX 유효성 검증 폴백(회색)을 그대로 재사용한다.
        colorHex: entry.colorHex ?? '',
        count: entry.count,
        ratio: entry.count / categoryTotal,
      ),
  ];

  final monthlyCounts = List<int>.filled(12, 0);
  for (final item in monthlyFiltered) {
    final month = item.finishedAt?.month;
    if (month == null) continue;
    monthlyCounts[month - 1]++;
  }
  final monthlyStats = [
    for (var month = 1; month <= 12; month++)
      ReadingStatsMonthly(month: month, count: monthlyCounts[month - 1]),
  ];

  // [BookItem.rereadCount]는 로컬/서버 모두 이미 "재독 횟수" 자체를
  // 담는 0-based 값이다(처음 완독한 책은 0, 이후 완독할 때마다 1씩 증가 —
  // `book_record_screen.dart`의 재독 팝업 참고). 서버 통계 API 문서의
  // "rereadCount - 1 기준"은 그쪽 원본 컬럼이 1-based(총 읽은 횟수)라 값을
  // 보정해서 내려준다는 뜻이라, 로컬 계산에서는 그대로 합산한다.
  final rereadCount = yearFiltered.fold<int>(
    0,
    (sum, item) => sum + item.rereadCount,
  );
  final masterpieceCount = yearFiltered
      .where((item) => item.isMasterpiece)
      .length;

  final ratings = [
    for (final item in yearFiltered)
      if (item.myRating != null) item.myRating!,
  ];
  final averageRating = ratings.isEmpty
      ? null
      : double.parse(
          (ratings.reduce((a, b) => a + b) / ratings.length).toStringAsFixed(1),
        );

  final publisherCounts = <String, int>{};
  for (final item in yearFiltered) {
    final publisher = item.publisher;
    if (publisher == null || publisher.isEmpty) continue;
    publisherCounts[publisher] = (publisherCounts[publisher] ?? 0) + 1;
  }
  String? mostReadPublisher;
  if (publisherCounts.isNotEmpty) {
    var bestCount = 0;
    for (final entry in publisherCounts.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        mostReadPublisher = entry.key;
      }
    }
  }

  return ReadingStatsSummary(
    finishedCount: yearFiltered.length,
    totalPages: totalPages,
    noteMemoCount: noteMemoCount,
    categoryStats: categoryStats,
    monthlyYear: monthlyYear,
    monthlyStats: monthlyStats,
    rereadCount: rereadCount,
    masterpieceCount: masterpieceCount,
    averageRating: averageRating,
    mostReadPublisher: mostReadPublisher,
  );
}

/// 연도 드롭다운 옵션(`stats-screen.md` §1-2). 완독 책의 [BookItem.finishedAt]
/// 연도를 중복 없이 최신순으로 추출한다.
List<int> computeReadingStatsYears(List<BookItem> finishedBooks) {
  final years = <int>{
    for (final item in finishedBooks)
      if (item.finishedAt case final finishedAt?) finishedAt.year,
  }.toList();
  years.sort((a, b) => b.compareTo(a));
  return years;
}
