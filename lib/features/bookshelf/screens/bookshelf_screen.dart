import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../models/book_status.dart';
import '../providers/bookshelf_providers.dart';
import 'widgets/finished_tab_view.dart';
import 'widgets/reading_tab_view.dart';
import 'widgets/simple_grid_tab_view.dart';

/// 내 책장(BOOKSHELF) 하단 탭 콘텐츠. 상태별 탭(읽을 책/읽는 중/완독/[읽기 중단]),
/// 읽기 중단 탭은 중단한 책이 1권 이상일 때만 노출한다.
///
/// 기본 선택 탭은 로컬 데이터의 최초 로딩이 끝난 시점에 "읽는 중 → 읽을 책 →
/// 읽는 중" 우선순위로 한 번만 결정하고, 이후 서버 동기화로 목록이 바뀌어도
/// 다시 바꾸지 않는다(사용자가 직접 고른 탭도 마찬가지). 다만 사용자가 보고
/// 있던 읽기 중단 탭이 데이터 변경으로 사라지는 경우에는 예외로 읽는 중
/// 탭으로 이동시킨다.
///
/// `bookshelf.md`: 탭 선택은 웹에서 sessionStorage로 유지되지만, 모바일에서는
/// [MainShell]의 `IndexedStack`이 탭 전환 시에도 이 위젯을 유지하므로
/// [TabController] 상태가 자연히 보존된다.
class BookshelfScreen extends ConsumerStatefulWidget {
  const BookshelfScreen({super.key});

  @override
  ConsumerState<BookshelfScreen> createState() => _BookshelfScreenState();
}

// 읽기 중단 탭이 항상 마지막 index라 노출/은닉으로 length가 3 ↔ 4로 바뀌어도
// 앞의 읽을 책(0)/읽는 중(1)/완독(2) index는 그대로 유지된다.
const _kStoppedTabIndex = 3;
const _kFinishedTabIndex = 2;
const _kReadingTabIndex = 1;
const _kWantToReadTabIndex = 0;

class _BookshelfScreenState extends ConsumerState<BookshelfScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _lastTabIndex = _kReadingTabIndex;
  bool _hasStoppedTab = false;
  bool _defaultTabResolved = false;
  bool _userSelectedTab = false;
  bool _applyingProgrammaticChange = false;
  bool _syncPending = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, initialIndex: 1, vsync: this)
      ..addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.index == _lastTabIndex) return;
    _lastTabIndex = _tabController.index;
    if (!_applyingProgrammaticChange) {
      _userSelectedTab = true;
    }
    // 완독 탭은 keep-alive라 검색 TextField의 FocusNode도 탭을 떠나도
    // 폐기되지 않는다 — 포커스를 둔 채 다른 탭으로 넘어가면 보이지 않는
    // 검색창이 계속 포커스를 들고 있어 키보드가 남는다. 검색어/필터/스크롤
    // 상태는 그대로 두고 키보드 포커스만 해제한다.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _setControllerIndex(int index) {
    _applyingProgrammaticChange = true;
    _tabController.index = index;
    _lastTabIndex = index;
    _applyingProgrammaticChange = false;
  }

  /// [status]에 대응하는 탭 index. 읽기 중단 탭이 아직 노출되지 않았는데
  /// 중단으로 바뀐 경우(그 신호가 도착한 프레임에는 아직 탭 노출 여부가
  /// 갱신되지 않았을 수 있음)에는 null을 반환해 이동을 건너뛴다 — 뒤이어
  /// `_syncTabControllerWithData`가 탭을 새로 노출시키면서 알아서 옮겨준다.
  int? _tabIndexForStatus(BookStatus status) {
    switch (status) {
      case BookStatus.wantToRead:
        return _kWantToReadTabIndex;
      case BookStatus.reading:
      case BookStatus.paused:
        return _kReadingTabIndex;
      case BookStatus.finished:
        return _kFinishedTabIndex;
      case BookStatus.stopped:
        return _hasStoppedTab ? _kStoppedTabIndex : null;
    }
  }

  void _recreateController({required int length, required int index}) {
    final oldController = _tabController;
    oldController.removeListener(_handleTabChanged);
    _tabController = TabController(length: length, initialIndex: index, vsync: this)
      ..addListener(_handleTabChanged);
    oldController.dispose();
    _lastTabIndex = index;
  }

  /// 기본 탭 결정과 읽기 중단 탭 노출 여부를 함께 반영한다. 두 로직이 각자
  /// 따로 컨트롤러를 건드리면 노출 변경(length 3 ↔ 4)과 기본 탭 index 결정이
  /// 같은 프레임에 겹칠 때 순서가 꼬일 수 있어, 실행 시점의 최신 provider
  /// 값을 다시 읽어 한 번에 반영한다.
  void _syncTabControllerWithData() {
    final readingAsync = ref.read(readingTabProvider);
    final wantToReadAsync = ref.read(gridTabProvider(BookStatus.wantToRead));
    final stoppedAsync = ref.read(gridTabProvider(BookStatus.stopped));

    // 기본 탭 결정: 로컬 최초 로딩(읽는 중 + 읽을 책 둘 다 값이 들어온
    // 시점)이 끝나기 전에는 로딩 중인 빈 상태를 "책이 없다"로 오판하지
    // 않도록 아무 것도 하지 않는다. 한 번 결정된 뒤에는(또는 사용자가 직접
    // 탭을 고른 뒤에는) 다시 실행하지 않는다.
    int? resolvedDefaultIndex;
    if (!_defaultTabResolved &&
        !_userSelectedTab &&
        readingAsync.hasValue &&
        wantToReadAsync.hasValue) {
      _defaultTabResolved = true;
      final hasReading = readingAsync.value!.isNotEmpty;
      final hasWantToRead = wantToReadAsync.value!.isNotEmpty;
      resolvedDefaultIndex = hasReading
          ? _kReadingTabIndex
          : (hasWantToRead ? _kWantToReadTabIndex : _kReadingTabIndex);
    }

    // 읽기 중단 탭 노출: 중단한 책이 1권 이상 있을 때만 보여준다. 현재
    // 선택된 읽기 중단 탭이 사라지는 경우에는 읽는 중 탭으로 이동시킨다.
    // 로딩·에러로 값을 아직 모르는 동안은(valueOrNull == null) 마지막으로
    // 알던 노출 상태를 그대로 유지한다 — 모름을 "비어 있음"으로 오판해
    // 탭이 껐다 켜지듯 깜빡이며 선택 탭이 흔들리는 것을 막는다.
    final shouldShowStopped =
        stoppedAsync.valueOrNull?.isNotEmpty ?? _hasStoppedTab;
    final wasOnStoppedTab =
        _hasStoppedTab && _tabController.index == _kStoppedTabIndex;
    final stoppedTabDisappeared = _hasStoppedTab && !shouldShowStopped;
    final newLength = shouldShowStopped ? 4 : 3;

    var newIndex = resolvedDefaultIndex ?? _tabController.index;
    if (stoppedTabDisappeared && wasOnStoppedTab) {
      newIndex = _kReadingTabIndex;
    }
    newIndex = newIndex.clamp(0, newLength - 1);

    if (newLength != _tabController.length) {
      _hasStoppedTab = shouldShowStopped;
      _recreateController(length: newLength, index: newIndex);
    } else if (newIndex != _tabController.index) {
      _setControllerIndex(newIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 최초 다운로드는 InitialRecordSyncGate가 맡는다. 진입 이후에는 동기화
    // 메타/오류와 무관하게 각 탭의 로컬 목록을 계속 보여준다.
    final readingAsync = ref.watch(readingTabProvider);
    final wantToReadAsync = ref.watch(gridTabProvider(BookStatus.wantToRead));
    final stoppedAsync = ref.watch(gridTabProvider(BookStatus.stopped));

    final needsDefaultResolution =
        !_defaultTabResolved &&
        !_userSelectedTab &&
        readingAsync.hasValue &&
        wantToReadAsync.hasValue;
    final shouldShowStopped =
        stoppedAsync.valueOrNull?.isNotEmpty ?? _hasStoppedTab;
    final needsStoppedTabUpdate = shouldShowStopped != _hasStoppedTab;

    if ((needsDefaultResolution || needsStoppedTabUpdate) && !_syncPending) {
      _syncPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncPending = false;
        if (!mounted) return;
        setState(_syncTabControllerWithData);
      });
    }

    // 책 기록 상세 화면에서 독서 상태를 바꾸고 돌아오면(그 화면은 이
    // IndexedStack 아래 계속 마운트된 채 유지됨) 바뀐 상태에 맞는 탭으로
    // 옮긴다. 사용자가 직접 고른 탭을 덮어써도 되는 이유: 방금 그 책의
    // 상태를 바꾼 행동 자체가 최신 의도이기 때문이다.
    ref.listen<BookStatus?>(lastBookStatusChangeProvider, (previous, next) {
      if (next == null) return;
      final index = _tabIndexForStatus(next);
      if (index != null && index != _tabController.index) {
        setState(() => _setControllerIndex(index));
      }
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.of(context).textStrong,
            unselectedLabelColor: AppColors.of(context).textMuted,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            indicator: BoxDecoration(
              color: AppColors.of(context).accentFill,
              borderRadius: BorderRadius.circular(999),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            // 기본 상태 레이어(hover/press/선택)가 알약 모양 indicator와
            // 무관하게 탭의 사각 영역 전체에 반투명 사각형으로 겹쳐 보여서
            // 모두 끈다 — 선택 표시는 위 pill indicator 하나로 충분하다.
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            dividerColor: Colors.transparent,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              const _PillTabLabel('읽을 책'),
              const _PillTabLabel('읽는 중'),
              const _PillTabLabel('완독'),
              if (_hasStoppedTab) const _PillTabLabel('읽기 중단'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              const SimpleGridTabView(
                status: BookStatus.wantToRead,
                emptyText: '읽을 책이 없습니다.',
              ),
              const ReadingTabView(),
              const FinishedTabView(),
              if (_hasStoppedTab)
                const SimpleGridTabView(
                  status: BookStatus.stopped,
                  emptyText: '읽기 중단한 책이 없습니다.',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PillTabLabel extends StatelessWidget {
  const _PillTabLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text),
    );
  }
}
