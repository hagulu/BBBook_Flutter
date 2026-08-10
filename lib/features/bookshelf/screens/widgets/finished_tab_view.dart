import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../book_record/screens/book_record_screen.dart';
import '../../models/book_item.dart';
import '../../models/finished_filter.dart';
import '../../providers/bookshelf_providers.dart';
import 'book_cover.dart';
import 'bookshelf_refresh_indicator.dart';
import 'finished_filter_panel.dart';
import 'finished_month_index_bar.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 완독 탭 상단 컨트롤(공개 토글/검색/필터 버튼) 영역 고정 높이.
///
/// `SliverAppBar.toolbarHeight`와 `_FinishedControls`의 내부 Column이 항상
/// 같은 값을 참조해야 한다 — 실제 콘텐츠 합계(128)보다 여유를 둔 값이라
/// RenderFlex 오버플로우 없이 안전하다.
const _kFinishedControlsHeight = 144.0;

/// 완독 탭 월 그룹 헤더 고정 높이. `_groupedSlivers`의 헤더 위젯과
/// `_FinishedTabViewState._offsetForGroupIndex`의 스크롤 오프셋 계산이
/// 항상 같은 값을 쓰도록 상수 하나로 공유한다(값이 어긋나면 인덱스 점프가 밀림).
const _kFinishedGroupHeaderHeight = 44.0;

/// 완독 탭 상단 컨트롤과 콘텐츠 사이 여백(스크롤 오프셋 계산에도 사용).
const _kFinishedContentSpacing = 4.0;

/// 그리드 셀(표지 2:3 + 제목 2줄 + 별점) 콘텐츠가 셀 높이를 넘지 않도록
/// 여유를 둔 비율. 0.56이면 좁은 화면에서 텍스트가 넘쳐 RenderFlex 오버플로우
/// (디버그 모드의 노란/검정 빗금)가 발생해 0.46으로 낮췄다.
const _kFinishedGridAspectRatio = 0.46;

/// 완독 탭: 검색/필터가 없는 기본 모드에서는 월별 그룹 그리드 + 우측 연/월
/// 인덱스(Google 포토 사진 스크러버 참고: 평소엔 얇은 트랙만 보이다 드래그 시
/// 손가락 옆에 날짜 버블이 뜬다), 검색/필터가 걸리면 일반 그리드로 전환한다
/// (`bookshelf.md`).
///
/// 상단 컨트롤(공개 토글/검색/필터 버튼)은 `SliverAppBar`(`floating: false`,
/// `pinned: false`)로 만들어 아래로 스크롤하면 사라진다. 다시 접근하려면
/// 목록 맨 위까지 스크롤해야 한다 — floating+snap(위로 스크롤 시 즉시
/// 재노출)은 아직 구현돼 있지 않다(TODO). 검색은 입력할 때마다 짧은
/// 디바운스 후 로컬 DB를 바로 재조회한다(버튼 없음).
class FinishedTabView extends ConsumerStatefulWidget {
  const FinishedTabView({super.key});

  @override
  ConsumerState<FinishedTabView> createState() => _FinishedTabViewState();
}

class _FinishedTabViewState extends ConsumerState<FinishedTabView> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _scrubNotifier = ValueNotifier<({String label, double dy})?>(null);
  final _filterPanelKey = GlobalKey();
  Timer? _searchDebounce;
  bool _filterPanelOpen = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _scrubNotifier.dispose();
    super.dispose();
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
    var offset = _kFinishedControlsHeight;
    if (_filterPanelOpen) {
      offset += _filterPanelKey.currentContext?.size?.height ?? 0;
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
    final filter = ref.watch(finishedFilterProvider);
    final books = ref.watch(finishedBooksProvider);
    final isDefaultMode = filter.isDefaultMode;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 썸/버블은 반투명 오버레이라 책 표지 위에 겹쳐도 되므로, 목록은
        // 항상 가로 전체 폭을 그대로 사용한다(오른쪽에 별도 여백을 두지 않음).
        final contentWidth = constraints.maxWidth;
        final groups = isDefaultMode
            ? books.maybeWhen(
                data: _groupByMonth,
                orElse: () => const <_MonthGroup>[],
              )
            : const <_MonthGroup>[];

        return Stack(
          children: [
            BookshelfRefreshIndicator(
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    backgroundColor: AppColors.pageBackground,
                    elevation: 0,
                    floating: false,
                    pinned: false,
                    automaticallyImplyLeading: false,
                    centerTitle: false,
                    titleSpacing: 0,
                    toolbarHeight: _kFinishedControlsHeight,
                    title: _FinishedControls(
                      searchController: _searchController,
                      onSearchChanged: _onSearchChanged,
                      onClearSearch: _clearSearch,
                      filterActiveCount: filter.activeCount,
                      onToggleFilterPanel: () =>
                          setState(() => _filterPanelOpen = !_filterPanelOpen),
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
                  ..._contentSlivers(filter, books, groups),
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

  List<Widget> _contentSlivers(
    FinishedFilter filter,
    AsyncValue<List<BookItem>> books,
    List<_MonthGroup> groups,
  ) {
    return books.when(
      data: (items) {
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
      },
      loading: () => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildMessage('불러오는 중'),
        ),
      ],
      error: (error, stackTrace) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildMessage(
            '목록을 불러오지 못했습니다.',
            onRetry: () => ref.invalidate(finishedBooksProvider),
          ),
        ),
      ],
    );
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
                    color: AppColors.titleText,
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
          Text(text, style: const TextStyle(color: AppColors.tertiaryText)),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
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

/// 완독 탭 상단 컨트롤 3줄(공개 토글 / 검색 / 필터 버튼). 높이는 항상
/// [_kFinishedControlsHeight]에 맞춰 `SliverAppBar`와 어긋나지 않게 한다.
class _FinishedControls extends ConsumerWidget {
  const _FinishedControls({
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.filterActiveCount,
    required this.onToggleFilterPanel,
    required this.onResetFilter,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final int filterActiveCount;
  final VoidCallback onToggleFilterPanel;
  final VoidCallback onResetFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacyState = ref.watch(privacySettingControllerProvider);
    final isPublic = privacyState.valueOrNull ?? false;

    return SizedBox(
      height: _kFinishedControlsHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: isPublic
                      ? '완독 책장 공개 중 (탭하면 비공개로 전환)'
                      : '완독 책장 비공개 중 (탭하면 공개로 전환)',
                  icon: Icon(
                    isPublic
                        ? PhosphorIconsRegular.globe
                        : PhosphorIconsRegular.lock,
                    color: AppColors.primary,
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('공개 설정 변경에 실패했습니다.'),
                                ),
                              );
                            }
                          }
                        },
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    PhosphorIconsRegular.question,
                    color: AppColors.mutedIcon,
                    size: 18,
                  ),
                  onPressed: () => AppAlert.show(
                    context,
                    title: '완독 책장 공개',
                    message: '공개로 설정하면 다른 사용자가 내 완독 책장을 볼 수 있습니다.',
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '책 이름, 작가, 출판사 검색',
                  filled: true,
                  fillColor: AppColors.inputBackground,
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
                    color: AppColors.tertiaryText,
                  ),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: searchController,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(
                          PhosphorIconsRegular.x,
                          size: 18,
                          color: AppColors.tertiaryText,
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
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
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
              BookCover(imageUrl: book.coverImageUrl, title: book.title),
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
                      color: AppColors.masterpieceGold,
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
              color: AppColors.titleText,
            ),
            maxLines: 2,
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
          color: i < filled ? AppColors.starFilled : AppColors.border,
        ),
      ),
    );
  }
}
