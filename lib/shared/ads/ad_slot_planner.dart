/// 목록/그리드 중간에 배너 광고를 몇 행마다 넣을지 계산하는 순수 함수들.
/// 완독 책장(그리드·리스트), 책 검색 결과, 독후감·토론·독자평 목록 등 여러
/// 화면이 함께 쓴다.
library;

/// [planRowBasedAdSlots]의 구간(월 그룹 등)별 결과. 그 구간을 얼마씩 나눠
/// 그릴지([chunks])와 그 묶음 뒤에 광고를 넣을지([adAfterChunk])를 담는다.
class GridAdPlan {
  const GridAdPlan(this.chunks, this.adAfterChunk);

  final List<int> chunks;
  final List<bool> adAfterChunk;
}

/// 목록은 월별 등 여러 구간(그룹)으로 나뉘어 그려질 수 있지만, 광고는 "책
/// 개수가 아니라 실제로 화면에 그려지는 행 수" 기준 [rowsPerAd]행마다
/// 하나씩, 구간 경계에서 사이클이 끊기지 않고 전체 목록을 이어서 센다.
/// 오직 전체 목록의 마지막 행 뒤에만 넣지 않는다(억지로 광고 조건을 추가
/// 하지 않음).
///
/// 그리드([crossAxisCount] > 1)에서는 각 구간이 독립된 `SliverGrid`로
/// 그려져(월이 바뀌면 새 행부터 시작) 구간의 마지막 행이 다 차지 않아도
/// (예: 3열 그리드에서 8권 = 3행, 마지막 행은 2칸만 참) 그 자리는 그대로
/// 한 행을 차지한다 — 그래서 항목 개수가 아니라 각 구간의
/// `ceil(항목 수 / crossAxisCount)`행을 누적해야, 광고가 실제 화면에 보이는
/// 행 수 기준으로 정확한 위치에 들어간다. 구간 중간에서 사이클 경계를
/// 만나 나눠야 할 때는(그 구간의 마지막 조각이 아닌 한) 행 단위로만
/// 자른다 — 그렇지 않으면 인위적으로 만든 조각에서도 같은 "마지막 행이
/// 덜 참" 문제가 생긴다.
///
/// 리스트 보기처럼 열이 없는(1열) 화면에서는 [crossAxisCount]를 1로 주면
/// 행 수와 항목 수가 같아져 기존의 "책 개수 기준" 계산과 동일하게 동작한다.
///
/// [segmentLengths]는 각 구간(월 그룹, 또는 구간이 없는 평면 모드면 구간
/// 1개)의 항목 개수다.
List<GridAdPlan> planRowBasedAdSlots({
  required List<int> segmentLengths,
  required int crossAxisCount,
  int rowsPerAd = 4,
}) {
  if (crossAxisCount <= 0 || rowsPerAd <= 0) {
    return [for (final _ in segmentLengths) const GridAdPlan([], [])];
  }

  int rowsFor(int itemCount) => (itemCount / crossAxisCount).ceil();
  final totalRows = segmentLengths.fold<int>(
    0,
    (sum, n) => sum + rowsFor(n),
  );

  var rowsConsumed = 0;
  final plans = <GridAdPlan>[];
  for (final length in segmentLengths) {
    final chunks = <int>[];
    final adAfterChunk = <bool>[];
    var remainingItems = length;
    var remainingRows = rowsFor(length);
    while (remainingRows > 0) {
      final posInCycle = rowsConsumed % rowsPerAd;
      final availableRows = rowsPerAd - posInCycle;
      final takeRows = remainingRows < availableRows
          ? remainingRows
          : availableRows;
      // 이 조각이 구간의 끝까지 이어지면(남은 행을 전부 가져가면) 구간의
      // 실제 나머지 항목을 그대로 담아 마지막(부분) 행을 보존한다. 아직
      // 구간이 끝나지 않은 중간 조각이면 행 단위로만 잘라 낸다.
      final takeItems = takeRows == remainingRows
          ? remainingItems
          : takeRows * crossAxisCount;
      chunks.add(takeItems);
      remainingItems -= takeItems;
      remainingRows -= takeRows;
      rowsConsumed += takeRows;
      final atCycleBoundary = rowsConsumed % rowsPerAd == 0;
      final isGlobalEnd = rowsConsumed == totalRows;
      adAfterChunk.add(atCycleBoundary && !isGlobalEnd);
    }
    plans.add(GridAdPlan(chunks, adAfterChunk));
  }
  return plans;
}

/// 열이 없는(1열) 단순 목록에 광고를 끼워 넣은 순서. [items]는 그대로
/// 두고(정렬·인덱스에 영향 없음) 그 사이사이에 광고 자리만 표시하는 별도
/// 항목을 추가한다. 더 불러오기로 [items]가 뒤에 계속 늘어나도 광고
/// 위치는 항상 같은 지점(N번째, 2N번째, ... 항목 뒤)을 가리키므로 이미
/// 지나간 위치가 다시 바뀌지 않는다.
sealed class AdSlotEntry<T> {}

class ItemAdSlotEntry<T> extends AdSlotEntry<T> {
  ItemAdSlotEntry(this.item);
  final T item;
}

class AdAdSlotEntry<T> extends AdSlotEntry<T> {
  AdAdSlotEntry(this.afterCount);

  /// 이 광고 슬롯 바로 앞까지 나온 항목 개수(광고 위젯의 안정적인 key로
  /// 쓸 수 있다).
  final int afterCount;
}

List<AdSlotEntry<T>> interleaveAdSlots<T>(
  List<T> items, {
  required int rowsPerAd,
}) {
  final plan = planRowBasedAdSlots(
    segmentLengths: [items.length],
    crossAxisCount: 1,
    rowsPerAd: rowsPerAd,
  ).first;

  final entries = <AdSlotEntry<T>>[];
  var start = 0;
  for (var i = 0; i < plan.chunks.length; i++) {
    final take = plan.chunks[i];
    for (final item in items.sublist(start, start + take)) {
      entries.add(ItemAdSlotEntry(item));
    }
    start += take;
    if (plan.adAfterChunk[i]) entries.add(AdAdSlotEntry(start));
  }
  return entries;
}
