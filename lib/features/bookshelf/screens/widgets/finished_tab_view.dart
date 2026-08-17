import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../book_record/screens/book_record_screen.dart';
import '../../models/book_item.dart';
import '../../models/finished_filter.dart';
import '../../providers/bookshelf_providers.dart';
import 'book_cover.dart';
import 'bookshelf_refresh_indicator.dart';
import 'bulk_isbn_link_banner.dart';
import 'finished_filter_panel.dart';
import 'finished_month_index_bar.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 완독 탭 상단 아이콘 바(공개 토글/도움말/검색 아이콘) 높이.
///
/// 고정(pinned)되지 않은 일반 콘텐츠 sliver라 목록과 함께 자연스럽게
/// 스크롤되어 사라진다. `_FinishedIconBar`의 내부 Row가 항상 같은 값을
/// 참조해야 한다. 44×44 터치 영역(아래 `_FinishedIconBar`)을 여백 없이
/// 꽉 채우지 않도록 44보다 조금 여유를 둔 값이다.
const _kFinishedIconBarHeight = 48.0;

/// 완독 탭 검색/필터 바(검색창 + 필터 버튼 행) 높이.
///
/// 아이콘 바의 검색 버튼을 누르면 접혔다 펼쳐지는 방식이라(스크롤 연동 아님)
/// [_FinishedTabViewState._searchOpen]이 false면 아예 트리에서 빠진다.
/// `_FinishedSearchBar`의 내부 Column이 항상 같은 값을 참조해야 한다 —
/// 실제 콘텐츠 합계(88)보다 여유를 둔 값이라 RenderFlex 오버플로우 없이 안전하다.
const _kFinishedSearchBarHeight = 96.0;

/// 완독 탭 월 그룹 헤더 고정 높이. `_groupedSlivers`의 헤더 위젯과
/// `_FinishedTabViewState._offsetForGroupIndex`의 스크롤 오프셋 계산이
/// 항상 같은 값을 쓰도록 상수 하나로 공유한다(값이 어긋나면 인덱스 점프가 밀림).
const _kFinishedGroupHeaderHeight = 44.0;

/// 완독 탭 상단 컨트롤과 콘텐츠 사이 여백(스크롤 오프셋 계산에도 사용).
const _kFinishedContentSpacing = 4.0;

/// 그리드 셀(표지 2:3 + 제목 1줄 + 별점) 콘텐츠가 셀 높이를 넘지 않도록
/// 여유를 둔 비율. 0.56이면 좁은 화면에서 텍스트가 넘쳐 RenderFlex 오버플로우
/// (디버그 모드의 노란/검정 빗금)가 발생해 0.46으로 낮췄다.
const _kFinishedGridAspectRatio = 0.46;

/// 완독 탭: 검색/필터가 없는 기본 모드에서는 월별 그룹 그리드 + 우측 연/월
/// 인덱스(Google 포토 사진 스크러버 참고: 평소엔 얇은 트랙만 보이다 드래그 시
/// 손가락 옆에 날짜 버블이 뜬다), 검색/필터가 걸리면 일반 그리드로 전환한다
/// (`bookshelf.md`).
///
/// 상단 컨트롤은 두 부분으로 나뉜다.
/// - 아이콘 바(공개 토글/도움말/검색 아이콘): 고정되지 않은 일반 sliver라
///   목록과 함께 자연스럽게 스크롤되어 사라진다(따로 고정해 둘 이유가
///   없다). 다만 [BookshelfScreen]이 이 CustomScrollView의 세로 스크롤
///   방향을 감지해 상단 탭 바(읽는 중/완독/읽고 싶음/중단)는 같은 타이밍에
///   접었다 펼친다.
/// - 검색/필터 바(`_FinishedSearchBar`): 검색창 + 필터 버튼. 스크롤과는
///   무관하게, 아이콘 바의 검색 버튼을 누를 때만 접혔다 펼쳐진다(토글). 펼칠
///   때는 목록을 맨 위로 스크롤해 바로 보이게 하고 검색창에 포커스를 준다.
///   닫으면(X) 검색을 "종료"하는 것으로 보고 검색어/필터도 함께 초기화한다.
///   검색은 입력할 때마다 짧은 디바운스 후 로컬 DB를 바로 재조회한다(버튼 없음).
class FinishedTabView extends ConsumerStatefulWidget {
  const FinishedTabView({super.key});

  @override
  ConsumerState<FinishedTabView> createState() => _FinishedTabViewState();
}

class _FinishedTabViewState extends ConsumerState<FinishedTabView>
    with AutomaticKeepAliveClientMixin<FinishedTabView> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _scrubNotifier = ValueNotifier<({String label, double dy})?>(null);
  final _filterPanelKey = GlobalKey();
  final _unlinkedBannerKey = GlobalKey();
  Timer? _searchDebounce;
  bool _searchOpen = false;
  bool _filterPanelOpen = false;

  // 월별 그룹 결과 캐시. `_groupByMonth`는 완독 전체 목록을 순회하는데,
  // 검색/필터 패널 토글처럼 books와 무관한 setState에도 build()가 다시
  // 실행되므로 캐시 없이는 매번 재계산된다. `books` 리스트가 실제로 바뀐
  // 경우(Riverpod가 새 List 인스턴스를 내려줄 때)만 다시 계산한다.
  List<BookItem>? _lastGroupedItems;
  List<_MonthGroup> _lastGroups = const [];

  // 마지막으로 "확정"(AsyncData)된 결과와, 그 결과를 만든 필터. 책 기록
  // 상세 등에서의 수정이 `bookshelfSyncVersionProvider`를 올려
  // [finishedBooksProvider]가 백그라운드에서 다시 조회되는 동안에도 화면이
  // 계속 이전 목록을 보여주게 하기 위한 캐시다(그러지 않으면 목록이
  // 통째로 사라졌다 다시 채워지면서 스크롤 위치가 맨 위로 리셋된 것처럼
  // 보인다). 단, 필터가 바뀐 뒤의 로딩 중에는 재사용하면 안 된다 — 필터가
  // 같을 때만([_lastSettledFilter] == 현재 필터) 재사용한다.
  FinishedFilter? _lastSettledFilter;
  List<BookItem>? _lastSettledItems;

  // PageView(TabBarView 내부)는 기본적으로 화면 밖으로 벗어난 탭의 State를
  // 그대로 폐기한다. 이 탭은 검색어/필터/스크롤 위치 등 내부 상태가 많고
  // 월별 그룹핑 비용도 있어, 다른 탭으로 갔다 돌아올 때마다 이를 처음부터
  // 다시 만들지 않도록 유지한다.
  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _scrubNotifier.dispose();
    super.dispose();
  }

  /// 아이콘 바의 검색 버튼: 검색/필터 바를 접었다 펼친다(스크롤과 무관한
  /// 단순 토글).
  void _toggleSearch() {
    if (_searchOpen) {
      _closeSearch();
    } else {
      _openSearch();
    }
  }

  /// 맨 위로 스크롤해 검색/필터 바를 바로 보이게 한다. 필터만 쓰려는
  /// 경우도 있어 키보드가 바로 뜨지 않도록 포커스는 주지 않는다(검색창을
  /// 직접 탭해야 포커스가 잡힌다).
  void _openSearch() {
    setState(() => _searchOpen = true);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// 검색 바를 닫는 것은 검색을 "종료"하는 의미이므로 검색어/필터도 함께
  /// 초기화한다(닫아도 검색어만 남아 있으면 그리드가 계속 필터된 상태로
  /// 남아 사용자가 혼란스러울 수 있다). 필터 패널을 여는 버튼도 검색 바
  /// 안에 있어 검색 바가 사라지면 접근할 수 없으므로 함께 닫는다.
  void _closeSearch() {
    _resetFilter();
    setState(() {
      _searchOpen = false;
      _filterPanelOpen = false;
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(finishedFilterProvider.notifier).setKeyword(value.trim());
      _resetScroll();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    ref.read(finishedFilterProvider.notifier).setKeyword('');
    _resetScroll();
  }

  void _resetFilter() {
    _searchDebounce?.cancel();
    _searchController.clear();
    ref.read(finishedFilterProvider.notifier).reset();
    _resetScroll();
  }

  /// 검색어/필터가 바뀌면 결과 집합과 그룹/그리드 구조 자체가 달라지므로,
  /// 스크롤 위치가 새 목록 범위를 벗어난 채(빈 화면) 남지 않도록 맨 위로 되돌린다.
  void _resetScroll() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// 월 인덱스 탭/드래그 시 해당 월로 이동한다.
  ///
  /// 그리드 delegate 상수가 고정돼 있으므로 각 그룹의 높이를 직접 계산해
  /// 오프셋으로 바로 점프한다(상단 컨트롤·필터 패널 높이를 더한 절대 위치).
  void _scrollToGroup(
    List<_MonthGroup> groups,
    double contentWidth,
    String groupKey,
  ) {
    if (!_scrollController.hasClients) return;
    final index = groups.indexWhere((g) => g.key == groupKey);
    if (index < 0) return;
    final offset =
        _contentStartOffset() +
        _offsetForGroupIndex(groups, index, contentWidth);
    final maxScroll = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(offset.clamp(0.0, maxScroll));
  }

  double _contentStartOffset() {
    var offset = _kFinishedIconBarHeight;
    // ISBN 미연결 배너는 있을 때만(그리고 권수에 따라 줄바꿈 여부도 달라질
    // 수 있어) 높이가 고정돼 있지 않다 — 필터 패널과 같은 방식으로 실제
    // 렌더링된 높이를 측정해 더한다(없으면 0).
    offset += _unlinkedBannerKey.currentContext?.size?.height ?? 0;
    if (_searchOpen) {
      offset += _kFinishedSearchBarHeight;
      if (_filterPanelOpen) {
        offset += _filterPanelKey.currentContext?.size?.height ?? 0;
      }
    }
    offset += _kFinishedContentSpacing;
    return offset;
  }

  double _offsetForGroupIndex(
    List<_MonthGroup> groups,
    int index,
    double contentWidth,
  ) {
    const crossAxisCount = 3;
    const crossAxisSpacing = 12.0;
    const mainAxisSpacing = 16.0;
    const horizontalPadding = 32.0; // SliverPadding 좌우 16 + 16

    final gridWidth = contentWidth - horizontalPadding;
    final tileWidth =
        (gridWidth - crossAxisSpacing * (crossAxisCount - 1)) / crossAxisCount;
    final tileHeight = tileWidth / _kFinishedGridAspectRatio;

    double offset = 0;
    for (var i = 0; i < index; i++) {
      final rows = (groups[i].items.length / crossAxisCount).ceil();
      final gridHeight = rows <= 0
          ? 0.0
          : rows * tileHeight + (rows - 1) * mainAxisSpacing;
      offset += _kFinishedGroupHeaderHeight + gridHeight;
    }
    return offset;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 요구사항
    final filter = ref.watch(finishedFilterProvider);
    final books = ref.watch(finishedBooksProvider);
    final isDefaultMode = filter.isDefaultMode;

    // 실제로 그릴 목록을 여기서 한 번만 정한다.
    // - AsyncData(확정된 성공 응답)면 그 값을 쓰고, 이 필터의 결과로 캐시해 둔다.
    // - AsyncLoading이고 캐시된 필터가 지금 필터와 같으면(=검색/필터가 아니라
    //   `bookshelfSyncVersionProvider` 변화로 인한 백그라운드 재조회) 캐시를
    //   그대로 재사용한다 — 그러지 않으면 목록이 통째로 사라졌다 다시
    //   채워지면서 스크롤 위치가 맨 위로 리셋된 것처럼 보인다.
    // - 그 외(필터가 바뀐 직후의 로딩, 또는 오류)는 재사용하지 않는다 —
    //   그러지 않으면 새 필터의 로딩/오류 중에 이전 필터의 결과가 그대로
    //   남아 사용자가 고른 조건과 다른 목록이 보일 수 있다.
    final List<BookItem>? items;
    if (books case AsyncData(:final value)) {
      items = value;
      _lastSettledFilter = filter;
      _lastSettledItems = value;
    } else if (books.isLoading && identical(_lastSettledFilter, filter)) {
      items = _lastSettledItems;
    } else {
      items = null;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 썸/버블은 반투명 오버레이라 책 표지 위에 겹쳐도 되므로, 목록은
        // 항상 가로 전체 폭을 그대로 사용한다(오른쪽에 별도 여백을 두지 않음).
        final contentWidth = constraints.maxWidth;
        final groups = isDefaultMode && items != null
            ? _groupedFor(items)
            : const <_MonthGroup>[];

        return Stack(
          children: [
            BookshelfRefreshIndicator(
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _FinishedIconBar(
                      searchOpen: _searchOpen,
                      onSearchTap: _toggleSearch,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: KeyedSubtree(
                      key: _unlinkedBannerKey,
                      child: const UnlinkedFinishedBanner(),
                    ),
                  ),
                  if (_searchOpen)
                    SliverToBoxAdapter(
                      child: _FinishedSearchBar(
                        searchController: _searchController,
                        searchFocusNode: _searchFocusNode,
                        onSearchChanged: _onSearchChanged,
                        onClearSearch: _clearSearch,
                        filterActiveCount: filter.activeCount,
                        onToggleFilterPanel: () => setState(
                          () => _filterPanelOpen = !_filterPanelOpen,
                        ),
                        onResetFilter: _resetFilter,
                      ),
                    ),
                  if (_filterPanelOpen)
                    SliverToBoxAdapter(
                      child: KeyedSubtree(
                        key: _filterPanelKey,
                        child: const FinishedFilterPanel(),
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: _kFinishedContentSpacing),
                  ),
                  ..._contentSlivers(filter, items, books.hasError, groups),
                ],
              ),
            ),
            if (isDefaultMode)
              Positioned(
                top: 8,
                bottom: 8,
                right: 0,
                width: FinishedMonthIndexBar.width,
                child: FinishedMonthIndexBar(
                  groups: [
                    for (final g in groups)
                      if (g.isDated)
                        (year: g.year, month: g.month, groupKey: g.key),
                  ],
                  scrollController: _scrollController,
                  onSelect: (groupKey) =>
                      _scrollToGroup(groups, contentWidth, groupKey),
                  onScrubChanged: (value) {
                    _scrubNotifier.value = value;
                    if (value != null && _filterPanelOpen) {
                      // 필터 패널이 열려 있으면 그 높이만큼 오프셋 계산이 어긋날 수
                      // 있어(측정 지연), 스크럽을 시작하면 패널을 닫아 기준을 고정한다.
                      setState(() => _filterPanelOpen = false);
                    }
                  },
                ),
              ),
            if (isDefaultMode)
              Positioned.fill(
                top: 8,
                bottom: 8,
                child: ValueListenableBuilder<({String label, double dy})?>(
                  valueListenable: _scrubNotifier,
                  builder: (context, scrub, _) {
                    if (scrub == null) return const SizedBox.shrink();
                    final bubbleTop = (scrub.dy - 18).clamp(
                      0.0,
                      constraints.maxHeight - 16 - 36,
                    );
                    return Stack(
                      children: [
                        Positioned(
                          // 손가락이 오른쪽 가장자리의 썸을 잡고 있는 동안에도 버블이
                          // 가려지지 않도록 썸 폭보다 한참 더 왼쪽에 띄운다.
                          right: FinishedMonthIndexBar.width + 40,
                          top: bubbleTop,
                          child: IgnorePointer(
                            child: _ScrubBubble(label: scrub.label),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  /// [items]는 build()에서 이미 "지금 필터에 안전하게 보여줘도 되는
  /// 데이터인지"까지 판단해 넘겨준 값이다(캐시 재사용 조건은 build() 문서
  /// 참고) — 여기서는 그 결과를 그대로 렌더링하기만 한다.
  List<Widget> _contentSlivers(
    FinishedFilter filter,
    List<BookItem>? items,
    bool hasError,
    List<_MonthGroup> groups,
  ) {
    if (items == null) {
      if (hasError) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildMessage(
              '목록을 불러오지 못했습니다.',
              onRetry: () => ref.invalidate(finishedBooksProvider),
            ),
          ),
        ];
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildMessage('불러오는 중'),
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildMessage(
            filter.isEmpty ? '완독한 책이 없습니다.' : '검색 결과가 없습니다.',
          ),
        ),
      ];
    }
    if (!filter.isDefaultMode) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              childAspectRatio: _kFinishedGridAspectRatio,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _FinishedBookCard(book: items[index]),
              childCount: items.length,
            ),
          ),
        ),
      ];
    }
    return _groupedSlivers(groups);
  }

  List<Widget> _groupedSlivers(List<_MonthGroup> groups) {
    return [
      for (final group in groups) ...[
        SliverToBoxAdapter(
          child: SizedBox(
            height: _kFinishedGroupHeaderHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  group.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              childAspectRatio: _kFinishedGridAspectRatio,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _FinishedBookCard(book: group.items[index]),
              childCount: group.items.length,
            ),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  Widget _buildMessage(String text, {VoidCallback? onRetry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: AppColors.textMuted)),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }

  /// [_lastGroupedItems]과 동일한 리스트 인스턴스면(=데이터가 실제로는
  /// 바뀌지 않았으면) 재계산하지 않고 캐시를 그대로 반환한다.
  List<_MonthGroup> _groupedFor(List<BookItem> items) {
    if (identical(_lastGroupedItems, items)) return _lastGroups;
    _lastGroupedItems = items;
    return _lastGroups = _groupByMonth(items);
  }

  /// `finishedAt`이 없는(예: CSV 가져오기 등으로 날짜 없이 완독 처리된) 책은
  /// 월별 그룹에서 누락시키지 않고 맨 끝에 "날짜 미지정" 그룹으로 모은다
  /// (우측 연/월 인덱스에는 노출하지 않되, 그리드에는 표시).
  List<_MonthGroup> _groupByMonth(List<BookItem> items) {
    final groups = <_MonthGroup>[];
    final undated = <BookItem>[];
    for (final item in items) {
      final finishedAt = item.finishedAt;
      if (finishedAt == null) {
        undated.add(item);
        continue;
      }
      if (groups.isNotEmpty &&
          groups.last.isDated &&
          groups.last.year == finishedAt.year &&
          groups.last.month == finishedAt.month) {
        groups.last.items.add(item);
      } else {
        groups.add(
          _MonthGroup(
            year: finishedAt.year,
            month: finishedAt.month,
            items: [item],
          ),
        );
      }
    }
    if (undated.isNotEmpty) {
      groups.add(_MonthGroup.undated(undated));
    }
    return groups;
  }
}

class _MonthGroup {
  _MonthGroup({required this.year, required this.month, required this.items})
    : isDated = true;

  _MonthGroup.undated(this.items) : year = 0, month = 0, isDated = false;

  final int year;
  final int month;
  final bool isDated;
  final List<BookItem> items;

  String get key => isDated ? '$year-$month' : 'no-date';
  String get label => isDated ? '$year년 $month월' : '날짜 미지정';
}

/// 완독 탭 상단 아이콘 바(검색 / 공개 토글 / 도움말). 고정되지 않은 일반
/// sliver 콘텐츠라 목록과 함께 스크롤되어 사라진다. 높이는 항상
/// [_kFinishedIconBarHeight]에 맞춰 `_contentStartOffset`의 계산과
/// 어긋나지 않게 한다.
class _FinishedIconBar extends ConsumerWidget {
  const _FinishedIconBar({required this.searchOpen, required this.onSearchTap});

  final bool searchOpen;
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacyState = ref.watch(privacySettingControllerProvider);
    final isPublic = privacyState.valueOrNull ?? false;

    return SizedBox(
      height: _kFinishedIconBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: EdgeInsets.zero,
              tooltip: searchOpen ? '검색 닫기' : '완독한 책 검색',
              icon: Icon(
                searchOpen
                    ? PhosphorIconsRegular.x
                    : PhosphorIconsRegular.magnifyingGlass,
                color: AppColors.accentForeground,
                size: 20,
              ),
              onPressed: onSearchTap,
            ),
            Row(
              children: [
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: isPublic
                      ? '완독 책장 공개 중 (탭하면 비공개로 전환)'
                      : '완독 책장 비공개 중 (탭하면 공개로 전환)',
                  icon: Icon(
                    isPublic
                        ? PhosphorIconsRegular.globe
                        : PhosphorIconsRegular.lock,
                    color: AppColors.accentForeground,
                    size: 20,
                  ),
                  onPressed: privacyState.isLoading
                      ? null
                      : () async {
                          try {
                            await ref
                                .read(privacySettingControllerProvider.notifier)
                                .toggle(!isPublic);
                          } catch (_) {
                            if (context.mounted) {
                              AppSnackBar.error(context, '공개 설정 변경에 실패했습니다.');
                            }
                          }
                        },
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: '완독 책장 공개 안내',
                  icon: const Icon(
                    PhosphorIconsRegular.question,
                    color: AppColors.controlInactive,
                    size: 18,
                  ),
                  onPressed: () => AppAlert.show(
                    context,
                    title: '완독 책장 공개',
                    message: '공개로 설정하면 다른 사용자가 내 완독 책장을 볼 수 있습니다.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 완독 탭 검색창 + 필터 버튼 행. 높이는 항상 [_kFinishedSearchBarHeight]에
/// 맞춰야 한다. 아이콘 바의 검색 버튼을 누를 때만 트리에 들어왔다 빠지는
/// 방식(스크롤과 무관한 단순 토글)이라 `SliverToBoxAdapter`로 감싸 쓴다.
class _FinishedSearchBar extends StatelessWidget {
  const _FinishedSearchBar({
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.filterActiveCount,
    required this.onToggleFilterPanel,
    required this.onResetFilter,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final int filterActiveCount;
  final VoidCallback onToggleFilterPanel;
  final VoidCallback onResetFilter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kFinishedSearchBarHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '책 이름, 작가, 출판사 검색',
                  filled: true,
                  fillColor: AppColors.surfaceSubtle,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  prefixIcon: const Icon(
                    PhosphorIconsRegular.magnifyingGlass,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: searchController,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(
                          PhosphorIconsRegular.x,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        onPressed: onClearSearch,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (filterActiveCount > 0)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: onResetFilter,
                      child: const Text(
                        '필터 초기화',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: onToggleFilterPanel,
                    icon: const Icon(PhosphorIconsRegular.funnel, size: 16),
                    label: Text(
                      filterActiveCount > 0 ? '필터 $filterActiveCount' : '필터',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrubBubble extends StatelessWidget {
  const _ScrubBubble({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentFill,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowStrong,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textStrong,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _FinishedBookCard extends StatelessWidget {
  const _FinishedBookCard({required this.book});

  final BookItem book;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookRecordScreen(userBookId: book.userBookId),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              BookCover(
                imageUrl: book.coverImageUrl,
                title: book.title,
                useDiskCache: true,
              ),
              if (book.isMasterpiece)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                    child: const Icon(
                      PhosphorIconsFill.crown,
                      size: 20,
                      color: AppColors.highlightGold,
                    ),
                  ),
                ),
              // ISBN(공용 book 연결)이 없는 책 표시. 완독 목록 상단
              // "ISBN 미연결 N권" 배너(bulk_isbn_link_banner.dart)로 일괄
              // 연결할 수 있는 대상이라, 표지에서도 바로 눈에 띄게 한다.
              if (book.isbn13 == null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Semantics(
                    label: 'ISBN 미연결',
                    child: Icon(
                      PhosphorIconsFill.linkBreak,
                      size: 14,
                      color: AppColors.error,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.textStrong,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (book.myRating != null) _StarRow(rating: book.myRating!),
        ],
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final filled = rating.round().clamp(0, 5);
    return Row(
      children: List.generate(
        5,
        (i) => Icon(
          i < filled ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
          size: 12,
          // 완독 목록에 표시되는 별점은 알라딘 회원 평점이 아니라 서비스 안에서
          // 직접 기록한 "내 평점"이라 아이덴티티 컬러로 구분한다.
          color: i < filled ? AppColors.accentGraphic : AppColors.border,
        ),
      ),
    );
  }
}
