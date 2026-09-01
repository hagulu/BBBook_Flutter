import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/book_search/screens/book_search_screen.dart';
import '../features/bookshelf/providers/bookshelf_providers.dart';
import '../features/bookshelf/screens/bookshelf_screen.dart';
import '../features/home/screens/home_tab_placeholder.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/profile/screens/profile_settings_screen.dart';
import '../shared/widgets/app_bar_title.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// 로그인 후 진입하는 하단 탭 셸(HOME/BOOKSHELF/PROFILE, `navigation.md` 대응).
///
/// HOME은 아직 최소 placeholder만 둔다. 기본 선택 탭은 실제로 동작하는
/// BOOKSHELF로 두어 로그인 직후 책장 목록이 바로 보이도록 한다. PROFILE
/// 탭 전용 설정(저장 방식 전환 등) 진입점은 이 셸의 AppBar 우측 설정
/// 아이콘으로 연결한다.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  static const _tabs = [
    HomeTabPlaceholder(),
    BookshelfScreen(),
    ProfileScreen(),
  ];

  int _selectedIndex = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncIfStale();
    }
  }

  void _syncIfStale() {
    ref.read(bookshelfSyncControllerProvider.notifier).syncIfStale();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('책책책'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
        actions: _selectedIndex == 2
            ? [
                IconButton(
                  icon: const Icon(PhosphorIconsRegular.gearSix),
                  tooltip: '설정',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfileSettingsScreen(),
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: IndexedStack(index: _selectedIndex, children: _tabs),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _NavItem(
                  icon: PhosphorIconsRegular.house,
                  selectedIcon: PhosphorIconsFill.house,
                  label: '홈',
                  selected: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                _NavItem(
                  icon: PhosphorIconsRegular.books,
                  selectedIcon: PhosphorIconsFill.books,
                  label: '책장',
                  selected: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                const _AddNavItem(),
                _NavItem(
                  icon: PhosphorIconsRegular.user,
                  selectedIcon: PhosphorIconsFill.user,
                  label: '마이',
                  selected: _selectedIndex == 2,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accentForeground : AppColors.textMuted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? selectedIcon : icon, color: color),
              const SizedBox(height: 2),
              // primaryDark와 textMuted의 색 대비가 크지 않아(둘 다 중간
              // 톤 초록) 아이콘 채움 변화 외에 글씨도 굵기로 선택 상태를
              // 한 번 더 구분한다.
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddNavItem extends StatelessWidget {
  const _AddNavItem();

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const BookSearchScreen())),
        child: Center(
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: AppColors.accentSurface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              PhosphorIconsRegular.plus,
              size: 20,
              color: AppColors.accentForeground,
            ),
          ),
        ),
      ),
    );
  }
}
