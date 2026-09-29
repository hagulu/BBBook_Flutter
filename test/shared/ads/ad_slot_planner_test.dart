import 'package:bbbook/shared/ads/ad_slot_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// 목록/그리드에 몇 행마다 배너 광고를 끼워 넣을지 계산하는 [planRowBasedAdSlots]의
/// 규칙을 검증한다(완독 책장 그리드/리스트, 책 검색 결과 목록이 공유하는 로직).
/// - 열 개수(crossAxisCount) 기준 [rowsPerAd]행마다 묶음을 나눈다.
/// - 월 그룹 등으로 여러 구간(segment)에 나뉘어도 사이클이 끊기지 않고
///   전체 목록을 이어서 센다.
/// - 오직 전체 목록의 마지막 묶음 뒤에는 광고를 넣지 않는다(=첫 화면에서
///   바로 광고가 보이지 않고, 콘텐츠를 충분히 본 뒤에야 만난다).
void main() {
  int totalAds(List<GridAdPlan> plans) => plans.fold(
    0,
    (sum, plan) => sum + plan.adAfterChunk.where((v) => v).length,
  );

  test('항목이 없으면 묶음도 광고도 없다', () {
    final plans = planRowBasedAdSlots(
      segmentLengths: [0],
      crossAxisCount: 3,
    );
    expect(plans.single.chunks, isEmpty);
    expect(totalAds(plans), 0);
  });

  test('한 구간 안에서 4행(12개) 미만이면 광고 없음', () {
    final plans = planRowBasedAdSlots(
      segmentLengths: [1],
      crossAxisCount: 3,
    );
    expect(plans.single.chunks, [1]);
    expect(totalAds(plans), 0);
  });

  test('정확히 12개(4행)를 채워도 그게 전체의 끝이면 광고 없음', () {
    final plans = planRowBasedAdSlots(
      segmentLengths: [12],
      crossAxisCount: 3,
    );
    expect(plans.single.chunks, [12]);
    expect(totalAds(plans), 0);
  });

  test('13개면 12개 뒤에 광고 1개, 마지막 1개 뒤에는 없음', () {
    final plans = planRowBasedAdSlots(
      segmentLengths: [13],
      crossAxisCount: 3,
    );
    expect(plans.single.chunks, [12, 1]);
    expect(plans.single.adAfterChunk, [true, false]);
    expect(totalAds(plans), 1);
  });

  test('한 구간(월)에 12개를 못 채워도, 다음 구간과 합쳐 4행을 넘기면 광고가 그 경계에 들어간다', () {
    // 1월 8권 + 2월 8권 = 16권. 1월은 3행(8권, 마지막 행 2칸만 참), 2월
    // 앞에서 1행(3권)을 더 가져와야 4행이 채워진다 — 경계는 "12번째 항목"이
    // 아니라 "4번째 행"이어야 한다(항목 수가 아니라 실제 행 수 기준).
    final plans = planRowBasedAdSlots(
      segmentLengths: [8, 8],
      crossAxisCount: 3,
    );
    expect(plans[0].chunks, [8]);
    expect(plans[0].adAfterChunk, [false]);
    expect(plans[1].chunks, [3, 5]);
    expect(plans[1].adAfterChunk, [true, false]);
    expect(totalAds(plans), 1);
  });

  test('월별 그리드는 항목 수가 아니라 각 달의 ceil(항목 수 / 열 수)행을 누적한다', () {
    // 리뷰에서 지적된 사례: 3열 그리드에서 8권인 달(3행, 마지막 행 2칸만
    // 참) + 11권인 달이 이어지면, 6행 경계는 "18번째 항목"이 아니라 실제
    // 누적 6행(1월 3행 + 2월 3행=9권) 지점에서 와야 한다.
    final plans = planRowBasedAdSlots(
      segmentLengths: [8, 11],
      crossAxisCount: 3,
      rowsPerAd: 6,
    );
    expect(plans[0].chunks, [8]);
    expect(plans[0].adAfterChunk, [false]);
    expect(plans[1].chunks, [9, 2]);
    expect(plans[1].adAfterChunk, [true, false]);
    expect(totalAds(plans), 1);
  });

  test('여러 구간에 걸쳐 4행 경계가 정확히 구간 끝과 맞아도(=마지막 구간 끝이 아니면) 광고가 들어간다', () {
    // 1월 12권(경계와 정확히 일치) + 2월 5권.
    final plans = planRowBasedAdSlots(
      segmentLengths: [12, 5],
      crossAxisCount: 3,
    );
    expect(plans[0].chunks, [12]);
    expect(plans[0].adAfterChunk, [true]);
    expect(plans[1].chunks, [5]);
    expect(plans[1].adAfterChunk, [false]);
    expect(totalAds(plans), 1);
  });

  test('37개면 12+12+12+1, 광고 3개(마지막 뒤에는 없음)', () {
    final plans = planRowBasedAdSlots(
      segmentLengths: [37],
      crossAxisCount: 3,
    );
    expect(plans.single.chunks, [12, 12, 12, 1]);
    expect(plans.single.adAfterChunk, [true, true, true, false]);
    expect(totalAds(plans), 3);
  });

  test('리스트 보기(1열)에서는 rowsPerAd만큼(6개)마다 광고가 들어간다', () {
    final plans = planRowBasedAdSlots(
      segmentLengths: [13],
      crossAxisCount: 1,
      rowsPerAd: 6,
    );
    expect(plans.single.chunks, [6, 6, 1]);
    expect(plans.single.adAfterChunk, [true, true, false]);
    expect(totalAds(plans), 2);
  });

  group('완독 그리드 실제 설정(3열, 8행 = 24개)', () {
    test('23개(8행 미만)면 첫 화면 스크롤만으로는 광고를 만나지 않는다(광고 없음)', () {
      final plans = planRowBasedAdSlots(
        segmentLengths: [23],
        crossAxisCount: 3,
        rowsPerAd: 8,
      );
      expect(plans.single.chunks, [23]);
      expect(totalAds(plans), 0);
    });

    test('25개면 24개 뒤에 광고 1개', () {
      final plans = planRowBasedAdSlots(
        segmentLengths: [25],
        crossAxisCount: 3,
        rowsPerAd: 8,
      );
      expect(plans.single.chunks, [24, 1]);
      expect(plans.single.adAfterChunk, [true, false]);
    });
  });

  group('완독 리스트·책 검색·독후감·토론·독자평 실제 설정(1열, 10행 = 10개)', () {
    test('10개(정확히 10행)를 채워도 전체의 끝이면 광고 없음', () {
      final plans = planRowBasedAdSlots(
        segmentLengths: [10],
        crossAxisCount: 1,
        rowsPerAd: 10,
      );
      expect(plans.single.chunks, [10]);
      expect(totalAds(plans), 0);
    });

    test('11개면 10개 뒤에 광고 1개', () {
      final plans = planRowBasedAdSlots(
        segmentLengths: [11],
        crossAxisCount: 1,
        rowsPerAd: 10,
      );
      expect(plans.single.chunks, [10, 1]);
      expect(plans.single.adAfterChunk, [true, false]);
    });

    test('더 불러오기로 항목이 계속 늘어나도(10→21개) 이미 정해진 10번째 뒤 광고 위치는 그대로다', () {
      final before = planRowBasedAdSlots(
        segmentLengths: [10],
        crossAxisCount: 1,
        rowsPerAd: 10,
      ).single;
      final after = planRowBasedAdSlots(
        segmentLengths: [21],
        crossAxisCount: 1,
        rowsPerAd: 10,
      ).single;
      expect(before.chunks, [10]);
      expect(after.chunks.take(1), [10]);
      expect(after.adAfterChunk.first, true);
    });
  });
}
