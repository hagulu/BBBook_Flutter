import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../models/book_status.dart';
import 'widgets/finished_tab_view.dart';
import 'widgets/reading_tab_view.dart';
import 'widgets/simple_grid_tab_view.dart';

/// 내 책장(BOOKSHELF) 하단 탭 콘텐츠. 상태별 4탭(읽을 책/읽는 중/완독/읽기 중단),
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
  // 탭 순서(읽을 책/읽는 중/완독/읽기 중단)상 읽는 중이 index 1이라 기본 선택
  // 탭으로 삼는다.
  late final TabController _tabController = TabController(
    length: 4,
    initialIndex: 1,
    vsync: this,
  );

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
    // 완독 탭은 keep-alive라 검색 TextField의 FocusNode도 탭을 떠나도
    // 폐기되지 않는다 — 포커스를 둔 채 다른 탭으로 넘어가면 보이지 않는
    // 검색창이 계속 포커스를 들고 있어 키보드가 남는다. 검색어/필터/스크롤
    // 상태는 그대로 두고 키보드 포커스만 해제한다.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    // 최초 다운로드는 InitialRecordSyncGate가 맡는다. 진입 이후에는
    // 동기화 메타/오류와 무관하게 각 탭의 로컬 목록을 계속 보여준다.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.textStrong,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            indicator: BoxDecoration(
              color: AppColors.accentFill,
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
            tabs: const [
              _PillTabLabel('읽을 책'),
              _PillTabLabel('읽는 중'),
              _PillTabLabel('완독'),
              _PillTabLabel('읽기 중단'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              SimpleGridTabView(
                status: BookStatus.wantToRead,
                emptyText: '읽을 책이 없습니다.',
              ),
              ReadingTabView(),
              FinishedTabView(),
              SimpleGridTabView(
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
