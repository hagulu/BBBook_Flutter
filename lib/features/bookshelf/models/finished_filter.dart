/// 완독 탭 검색/필터 상태. 모두 로컬 DB 쿼리 조건으로 변환된다.
class FinishedFilter {
  const FinishedFilter({
    this.keyword = '',
    this.includeRecords = false,
    this.categories = const {},
    this.tagIds = const {},
    this.masterpieceOnly = false,
    this.difficulty,
  });

  final String keyword;

  /// 검색어를 책 정보(제목·작가·출판사)뿐 아니라 내가 쓴 메모·독후감 본문에서도
  /// 찾을지 여부. 검색 범위 옵션일 뿐 그 자체로 목록을 거르지는 않으므로
  /// 검색어가 비어 있으면 결과에 영향이 없다 — [isEmpty]/[activeCount]에 넣지 않는다.
  final bool includeRecords;

  /// 지금 검색 결과가 메모·독후감 내용에 좌우되는지. 이 값이 true일 때만
  /// 기록 변경(동기화·편집)에 맞춰 결과를 다시 조회하면 된다.
  bool get searchesRecords => includeRecords && keyword.isNotEmpty;

  /// 책 하나당 카테고리는 하나뿐이지만, 필터에서는 여러 카테고리를 선택해
  /// "그 중 하나라도 해당"(OR)으로 걸러낼 수 있다.
  final Set<String> categories;
  final Set<int> tagIds;
  final bool masterpieceOnly;
  final String? difficulty;

  bool get isEmpty =>
      keyword.isEmpty &&
      categories.isEmpty &&
      tagIds.isEmpty &&
      !masterpieceOnly &&
      difficulty == null;

  /// 월별 그룹 + 우측 인덱스는 검색/필터가 걸리지 않은 기본 모드에서만 노출한다
  /// (bookshelf.md: 필터/검색 시 일반 목록으로 전환).
  bool get isDefaultMode => isEmpty;

  /// 검색어는 필터 기준이 아니라 별도 검색이라 이 개수에 포함하지 않는다
  /// — 필터 버튼 배지/초기화 버튼은 카테고리·태그·명작·난이도 기준만 본다.
  int get activeCount =>
      (categories.isNotEmpty ? 1 : 0) +
      (tagIds.isNotEmpty ? 1 : 0) +
      (masterpieceOnly ? 1 : 0) +
      (difficulty != null ? 1 : 0);

  FinishedFilter copyWith({
    String? keyword,
    bool? includeRecords,
    Set<String>? categories,
    Set<int>? tagIds,
    bool? masterpieceOnly,
    String? difficulty,
    bool clearDifficulty = false,
  }) {
    return FinishedFilter(
      keyword: keyword ?? this.keyword,
      includeRecords: includeRecords ?? this.includeRecords,
      categories: categories ?? this.categories,
      tagIds: tagIds ?? this.tagIds,
      masterpieceOnly: masterpieceOnly ?? this.masterpieceOnly,
      difficulty: clearDifficulty ? null : (difficulty ?? this.difficulty),
    );
  }
}
