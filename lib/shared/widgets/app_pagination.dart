import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 페이지 번호 목록을 계산한다(1부터 시작). 항상 첫 페이지·마지막 페이지를
/// 포함하고, 현재 페이지 좌우 [siblingCount]개만 보여준 뒤 나머지는 `null`
/// (말줄임 `···`)로 접는다. 예: current=9, totalPages=32 →
/// `[1, null, 7, 8, 9, 10, 11, null, 32]`.
List<int?> buildPaginationRange({
  required int currentPage,
  required int totalPages,
  int siblingCount = 2,
  int boundaryCount = 1,
}) {
  if (totalPages <= 0) return const [];

  final totalNumbers = siblingCount * 2 + boundaryCount * 2 + 3;
  if (totalNumbers >= totalPages) {
    return List.generate(totalPages, (i) => i + 1);
  }

  final leftSibling = (currentPage - siblingCount).clamp(
    boundaryCount + 1,
    totalPages,
  );
  final rightSibling = (currentPage + siblingCount).clamp(
    1,
    totalPages - boundaryCount,
  );

  final showLeftEllipsis = leftSibling > boundaryCount + 2;
  final showRightEllipsis = rightSibling < totalPages - boundaryCount - 1;

  if (!showLeftEllipsis && showRightEllipsis) {
    final leftCount = boundaryCount + siblingCount * 2 + 2;
    return [...List.generate(leftCount, (i) => i + 1), null, totalPages];
  }

  if (showLeftEllipsis && !showRightEllipsis) {
    final rightCount = boundaryCount + siblingCount * 2 + 2;
    return [
      1,
      null,
      ...List.generate(rightCount, (i) => totalPages - rightCount + i + 1),
    ];
  }

  if (showLeftEllipsis && showRightEllipsis) {
    return [
      1,
      null,
      ...List.generate(
        rightSibling - leftSibling + 1,
        (i) => leftSibling + i,
      ),
      null,
      totalPages,
    ];
  }

  return List.generate(totalPages, (i) => i + 1);
}

/// 공통 숫자 페이지네이션. 항상 첫/마지막 페이지를 보여주고 현재 페이지
/// 주변만 펼치며 나머지는 `···`로 접는다(터치 영역 44px 확보, 현재 페이지만
/// 강조하는 간결한 디자인).
class AppPagination extends StatelessWidget {
  const AppPagination({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.siblingCount = 2,
  });

  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  /// 현재 페이지 좌우로 펼쳐 보일 개수. 좁은 폭에 놓일 때(예: 화면 안에
  /// 다른 콘텐츠와 함께 배치되는 경우) 줄여서 양쪽 끝이 스크롤 없이 보이게
  /// 할 수 있다.
  final int siblingCount;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    final range = buildPaginationRange(
      currentPage: currentPage,
      totalPages: totalPages,
      siblingCount: siblingCount,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in range)
            entry == null
                ? const _PaginationEllipsis()
                : _PaginationItem(
                    page: entry,
                    isCurrent: entry == currentPage,
                    onTap: entry == currentPage
                        ? null
                        : () => onPageChanged(entry),
                  ),
        ],
      ),
    );
  }
}

class _PaginationItem extends StatelessWidget {
  const _PaginationItem({
    required this.page,
    required this.isCurrent,
    required this.onTap,
  });

  final int page;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isCurrent,
      label: '$page페이지${isCurrent ? ', 현재 페이지' : ''}',
      child: ExcludeSemantics(
        child: Material(
          color: isCurrent ? AppColors.accentSurface : Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: Text(
                '$page',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  color: isCurrent
                      ? AppColors.accentForeground
                      : AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaginationEllipsis extends StatelessWidget {
  const _PaginationEllipsis();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 32,
      height: 44,
      child: Center(
        child: Text(
          '···',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ),
    );
  }
}
