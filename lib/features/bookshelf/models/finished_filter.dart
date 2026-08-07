/// 완독 탭 검색/필터 상태. 모두 로컬 DB 쿼리 조건으로 변환된다.
class FinishedFilter {
  const FinishedFilter({
    this.keyword = '',
    this.category,
    this.tagIds = const {},
    this.masterpieceOnly = false,
    this.difficulty,
  });

  final String keyword;
  final String? category;
  final Set<int> tagIds;
  final bool masterpieceOnly;
  final String? difficulty;

  bool get isEmpty =>
      keyword.isEmpty &&
      category == null &&
      tagIds.isEmpty &&
      !masterpieceOnly &&
      difficulty == null;

  /// 월별 그룹 + 우측 인덱스는 검색/필터가 걸리지 않은 기본 모드에서만 노출한다
  /// (bookshelf.md: 필터/검색 시 일반 목록으로 전환).
  bool get isDefaultMode => isEmpty;

  int get activeCount =>
      (keyword.isNotEmpty ? 1 : 0) +
      (category != null ? 1 : 0) +
      (tagIds.isNotEmpty ? 1 : 0) +
      (masterpieceOnly ? 1 : 0) +
      (difficulty != null ? 1 : 0);

  FinishedFilter copyWith({
    String? keyword,
    String? category,
    bool clearCategory = false,
    Set<int>? tagIds,
    bool? masterpieceOnly,
    String? difficulty,
    bool clearDifficulty = false,
  }) {
    return FinishedFilter(
      keyword: keyword ?? this.keyword,
      category: clearCategory ? null : (category ?? this.category),
      tagIds: tagIds ?? this.tagIds,
      masterpieceOnly: masterpieceOnly ?? this.masterpieceOnly,
      difficulty: clearDifficulty ? null : (difficulty ?? this.difficulty),
    );
  }
}
