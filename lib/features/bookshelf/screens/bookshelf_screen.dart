import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../models/book_status.dart';
import '../providers/bookshelf_providers.dart';
import 'widgets/finished_tab_view.dart';
import 'widgets/reading_tab_view.dart';
import 'widgets/simple_grid_tab_view.dart';

/// 내 책장(BOOKSHELF) 하단 탭 콘텐츠. 상태별 4탭(읽고 싶음/읽는 중/완독/중단),
/// 기본 선택 탭은 읽는 중.
///
/// `bookshelf.md`: 탭 선택은 웹에서 sessionStorage로 유지되지만, 모바일에서는
/// [MainShell]의 `IndexedStack`이 탭 전환 시에도 이 위젯을 유지하므로
/// [TabController] 상태가 자연히 보존된다.
class BookshelfScreen extends ConsumerStatefulWidget {
  const BookshelfScreen({super.key});

  @override
  ConsumerState<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends ConsumerState<BookshelfScreen>
    with SingleTickerProviderStateMixin {
  // 탭 순서(읽고 싶음/읽는 중/완독/중단)상 읽는 중이 index 1이라 기본 선택
  // 탭으로 삼는다.
  late final TabController _tabController = TabController(
    length: 4,
    initialIndex: 1,
    vsync: this,
  );

  // 탭 내부 콘텐츠가 맨 위(pixels <= 0)가 아니면 이 탭 바(및 완독 탭 내부
  // 아이콘 행)를 무조건 접어 숨긴다. 스크롤 방향은 보지 않는다 — 중간에
  // 위로 스크롤한다고 다시 보여줄 필요는 없고, 맨 위로 돌아왔을 때만 다시
  // 나타난다.
  bool _chromeVisible = true;

  // 탭마다 별도 스크롤 컨트롤러를 갖고 있어(각자 마지막 스크롤 위치를 그대로
  // 유지), 다른 탭에서 스크롤을 내려 탭 바를 숨긴 채로 다른 탭으로 넘어가면
  // 그 탭이 맨 위여도 탭 바가 계속 숨어 있을 수 있다 — 탭이 바뀔 때는 목적지
  // 탭의 실제 스크롤 위치와 무관하게 무조건 다시 보여준다.
  int _lastTabIndex = 1;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_handleTabChanged);
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
    _setChromeVisible(true);
  }

  void _setChromeVisible(bool visible) {
    if (_chromeVisible != visible) {
      setState(() => _chromeVisible = visible);
    }
  }

  /// `TabBarView`(가로 `PageView`)의 탭 전환 스크롤은 무시하고, 각 탭
  /// 콘텐츠(세로 스크롤)의 현재 위치만으로 탭 바 노출 여부를 정한다.
  bool _handleScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    _setChromeVisible(metrics.pixels <= 0);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // 탭들은 각자 로컬 DB 조회 provider만 보고 있어, 로컬에 아직 아무 데이터도
    // 없는 최초 동기화 중에는 그냥 "없습니다"로 보이고 실패해도 원인을 알 수
    // 없다. 최초 동기화(lastSyncedAt == null)가 진행 중이거나 실패한 동안만
    // 이 화면에서 로딩/에러로 대체한다 — 최초 동기화가 끝난 뒤의 갱신은 기존
    // 로컬 목록/RefreshIndicator SnackBar로 계속 처리한다.
    final syncState = ref.watch(bookshelfSyncControllerProvider);
    final isInitialSync = syncState.valueOrNull == null;

    if (isInitialSync && syncState.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '책장을 불러오지 못했습니다.',
              style: TextStyle(color: AppColors.tertiaryText),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.read(bookshelfSyncControllerProvider.notifier).syncNow(),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    if (isInitialSync && syncState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            heightFactor: _chromeVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.tertiaryText,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                tabs: const [
                  _PillTabLabel('읽고 싶음'),
                  _PillTabLabel('읽는 중'),
                  _PillTabLabel('완독'),
                  _PillTabLabel('중단'),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: TabBarView(
              controller: _tabController,
              children: const [
                SimpleGridTabView(
                  status: BookStatus.wantToRead,
                  emptyText: '읽고 싶은 책이 없습니다.',
                ),
                ReadingTabView(),
                FinishedTabView(),
                SimpleGridTabView(
                  status: BookStatus.stopped,
                  emptyText: '중단한 책이 없습니다.',
                ),
              ],
            ),
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
