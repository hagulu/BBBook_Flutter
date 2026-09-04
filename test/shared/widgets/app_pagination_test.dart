import 'package:bbbook/shared/widgets/app_pagination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('전체 페이지가 적으면 생략 없이 모두 보여준다', () {
    final range = buildPaginationRange(currentPage: 3, totalPages: 6);
    expect(range, [1, 2, 3, 4, 5, 6]);
  });

  test('현재 페이지가 앞쪽이면 오른쪽만 생략한다', () {
    final range = buildPaginationRange(currentPage: 2, totalPages: 32);
    expect(range, [1, 2, 3, 4, 5, 6, 7, null, 32]);
  });

  test('현재 페이지가 뒤쪽이면 왼쪽만 생략한다', () {
    final range = buildPaginationRange(currentPage: 31, totalPages: 32);
    expect(range, [1, null, 26, 27, 28, 29, 30, 31, 32]);
  });

  test('현재 페이지가 중간이면 양쪽 다 생략하고 항상 첫/마지막을 포함한다', () {
    final range = buildPaginationRange(currentPage: 9, totalPages: 32);
    expect(range, [1, null, 7, 8, 9, 10, 11, null, 32]);
  });

  test('페이지가 하나뿐이면 그 하나만 반환한다', () {
    expect(buildPaginationRange(currentPage: 1, totalPages: 1), [1]);
  });

  test('총 페이지가 0 이하이면 빈 목록을 반환한다', () {
    expect(buildPaginationRange(currentPage: 1, totalPages: 0), isEmpty);
  });
}
