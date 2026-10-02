import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/providers/auth_notifier.dart';
import '../features/book_search/screens/book_search_screen.dart';
import '../features/bookshelf/providers/bookshelf_providers.dart';
import '../features/bookshelf/screens/bookshelf_screen.dart';
import '../features/notices/providers/notices_providers.dart';
import '../features/notices/widgets/important_notice_dialog.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/profile/screens/profile_settings_screen.dart';
import '../features/record_sync/providers/background_record_sync_provider.dart';
import '../shared/widgets/app_bar_title.dart';
import '../shared/widgets/app_confirm.dart';
import 'main_shell_layout.dart';
import 'main_shell_tab_provider.dart';

const double _floatingNavBlurSigma = 12;
const double _floatingNavSurfaceOpacity = 0.50;

List<BoxShadow> _floatingNavShadows(AppPalette colors) => [
  BoxShadow(
    color: colors.shadowSoft,
    blurRadius: 8,
    spreadRadius: -2,
    offset: const Offset(0, 1),
  ),
  BoxShadow(
    color: colors.shadowStrong,
    blurRadius: 12,
    spreadRadius: -4,
    offset: const Offset(0, 8),
  ),
];

class _OuterShadowPainter extends CustomPainter {
  const _OuterShadowPainter({
    required this.borderRadius,
    required this.shadows,
  });

  final BorderRadius borderRadius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = borderRadius.toRRect(Offset.zero & size);
    const shadowMargin = 32.0;
    final exterior = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(
        Rect.fromLTRB(
          -shadowMargin,
          -shadowMargin,
          size.width + shadowMargin,
          size.height + shadowMargin,
        ),
      )
      ..addRRect(shape);

    canvas.save();
    canvas.clipPath(exterior, doAntiAlias: true);
    for (final shadow in shadows) {
      final shadowShape = shape
          .inflate(shadow.spreadRadius)
          .shift(shadow.offset);
      canvas.drawRRect(shadowShape, shadow.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      !listEquals(oldDelegate.shadows, shadows);
}

/// 로그인 후 진입하는 하단 탭 셸(BOOKSHELF/PROFILE, `navigation.md` 대응).
///
/// 기본 선택 탭은 BOOKSHELF로 두어 로그인 직후 책장 목록이 바로 보이도록
/// 한다. 가운데 "책 추가" 탭은 책 검색으로 연결하고, PROFILE 탭 전용 설정
/// (저장 방식 전환 등) 진입점은 이 셸의 AppBar 우측 설정 아이콘으로 연결한다.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  static const _tabs = [BookshelfScreen(), ProfileScreen()];

  bool _checkingImportantNotice = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshCategoriesIfStale());
    // 셸이 처음 뜬 뒤 중요 공지 팝업을 한 번 확인한다.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkImportantNotice(),
    );
  }

  /// 중요 공지 팝업 확인. 이미 확인 중이거나 팝업이 떠 있으면 중복으로 띄우지 않는다.
  Future<void> _checkImportantNotice() async {
    if (!mounted || _checkingImportantNotice) return;
    _checkingImportantNotice = true;
    try {
      await showImportantNoticeIfNeeded(context, ref);
    } finally {
      _checkingImportantNotice = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshCategoriesIfStale());
      unawaited(_checkImportantNotice());
      ref.invalidate(hasNewNoticeProvider);
      // 징계 해제는 서버 상태를 다시 읽어야 반영된다. 앱 복귀 때만 확인한다.
      if (ref.read(authNotifierProvider).user?.isSanctioned == true) {
        unawaited(ref.read(authNotifierProvider.notifier).refreshCurrentUser());
      }
    }
  }

  /// 카테고리 마스터 목록이 오래됐으면(기본 24시간) 서버에서 다시 받아온다.
  /// 앱 실행 직후와 포그라운드 복귀 시 모두 호출한다. `unawaited`로 호출되므로
  /// 오프라인·서버 오류가 앱 전역 처리되지 않은 예외로 새지 않도록 여기서
  /// 직접 잡아 로그만 남긴다(로그인 시점 강제 갱신인
  /// [AuthNotifier._prefetchCategories]와 동일한 방침).
  Future<void> _refreshCategoriesIfStale() async {
    try {
      final refreshed = await ref
          .read(bookshelfRepositoryProvider)
          .refreshCategoriesIfStale();
      if (refreshed && mounted) ref.invalidate(bookCategoriesProvider);
    } catch (e) {
      developer.log('[카테고리 갱신] result=FAIL reason=${e.runtimeType}');
    }
  }

  Future<void> _handlePopAttempt(bool didPop) async {
    if (didPop) return;
    final confirmed = await AppConfirm.show(
      context,
      title: '앱 종료',
      message: '앱을 종료할까요?',
      confirmText: '종료',
    );
    if (confirmed) {
      SystemNavigator.pop();
    }
  }

  Future<void> _openBookSearch() {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const BookSearchScreen(),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(backgroundRecordSyncProvider);
    final selectedIndex = ref.watch(mainShellTabIndexProvider);
    final hasNewNotice = ref.watch(hasNewNoticeProvider).valueOrNull ?? false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handlePopAttempt(didPop),
      child: Scaffold(
        appBar: AppBar(
          title: const AppBarTitle('북꾸러미'),
          backgroundColor: AppColors.of(context).pageBackground,
          foregroundColor: AppColors.of(context).textStrong,
          elevation: 0,
          actions: selectedIndex == 1
              ? [
                  IconButton(
                    icon: Badge(
                      isLabelVisible: hasNewNotice,
                      smallSize: 8,
                      backgroundColor: AppColors.of(context).error,
                      child: const Icon(PhosphorIconsRegular.gearSix),
                    ),
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
        body: Stack(
          fit: StackFit.expand,
          children: [
            IndexedStack(index: selectedIndex, children: _tabs),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(
                  MainShellNavigationLayout.minimumHorizontalInset,
                  0,
                  MainShellNavigationLayout.minimumHorizontalInset,
                  MainShellNavigationLayout.minimumBottomInset,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: MainShellNavigationLayout.bottomLift,
                  ),
                  child: BackdropGroup(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FloatingNavPill(
                          items: [
                            _FloatingNavPillItem(
                              icon: PhosphorIconsRegular.books,
                              selectedIcon: PhosphorIconsFill.books,
                              label: '책장',
                              selected: selectedIndex == 0,
                              onTap: () =>
                                  ref
                                          .read(
                                            mainShellTabIndexProvider.notifier,
                                          )
                                          .state =
                                      0,
                            ),
                            _FloatingNavPillItem(
                              icon: PhosphorIconsRegular.user,
                              selectedIcon: PhosphorIconsFill.user,
                              label: '마이',
                              selected: selectedIndex == 1,
                              onTap: () =>
                                  ref
                                          .read(
                                            mainShellTabIndexProvider.notifier,
                                          )
                                          .state =
                                      1,
                            ),
                          ],
                        ),
                        const SizedBox(
                          width: MainShellNavigationLayout.controlGap,
                        ),
                        _AddBookButton(onTap: _openBookSearch),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 콘텐츠 위에 떠 있는 pill 형태의 하단 Navigation(Google Photos 참고).
class _FloatingNavPill extends StatelessWidget {
  const _FloatingNavPill({required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final borderRadius = BorderRadius.circular(999);
    return CustomPaint(
      painter: _OuterShadowPainter(
        borderRadius: borderRadius,
        shadows: _floatingNavShadows(colors),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter.grouped(
          filter: ui.ImageFilter.blur(
            sigmaX: _floatingNavBlurSigma,
            sigmaY: _floatingNavBlurSigma,
          ),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: MainShellNavigationLayout.controlSize,
            ),
            padding: const EdgeInsets.all(MainShellNavigationLayout.outerInset),
            decoration: BoxDecoration(
              color: colors.surface.withValues(
                alpha: _floatingNavSurfaceOpacity,
              ),
              borderRadius: borderRadius,
              border: Border.all(color: colors.border.withValues(alpha: 0.65)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: items),
          ),
        ),
      ),
    );
  }
}

class _FloatingNavPillItem extends StatelessWidget {
  const _FloatingNavPillItem({
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
    final colors = AppColors.of(context);
    final usesStackedLabels = MainShellNavigationLayout.usesStackedLabels(
      context,
    );
    final textColor = selected ? colors.textStrong : colors.textMuted;
    final selectedColor = Color.lerp(
      colors.accentSurface,
      colors.accentFill,
      0.7,
    )!;
    final iconWidget = Icon(
      selected ? selectedIcon : icon,
      color: textColor,
      size: MainShellNavigationLayout.iconSize,
    );
    final labelWidget = Text(
      label,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: textColor,
        fontSize: MainShellNavigationLayout.labelFontSize,
        height: 1,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: AnimatedContainer(
          duration: selected
              ? const Duration(milliseconds: 250)
              : Duration.zero,
          curve: Curves.easeOut,
          constraints: const BoxConstraints(
            minHeight: MainShellNavigationLayout.itemMinHeight,
          ),
          padding: usesStackedLabels
              ? const EdgeInsets.symmetric(
                  horizontal:
                      MainShellNavigationLayout.stackedItemHorizontalPadding,
                  vertical:
                      MainShellNavigationLayout.stackedItemVerticalPadding,
                )
              : const EdgeInsets.symmetric(
                  horizontal: MainShellNavigationLayout.itemHorizontalPadding,
                ),
          decoration: BoxDecoration(
            color: selected ? selectedColor : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: usesStackedLabels
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconWidget,
                    const SizedBox(
                      height: MainShellNavigationLayout.stackedIconLabelGap,
                    ),
                    labelWidget,
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconWidget,
                    const SizedBox(
                      width: MainShellNavigationLayout.iconLabelGap,
                    ),
                    labelWidget,
                  ],
                ),
        ),
      ),
    );
  }
}

class _AddBookButton extends StatelessWidget {
  const _AddBookButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final borderRadius = BorderRadius.circular(
      MainShellNavigationLayout.controlSize / 2,
    );
    return Semantics(
      button: true,
      label: '책 추가',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: CustomPaint(
          painter: _OuterShadowPainter(
            borderRadius: borderRadius,
            shadows: _floatingNavShadows(colors),
          ),
          child: ClipOval(
            child: BackdropFilter.grouped(
              filter: ui.ImageFilter.blur(
                sigmaX: _floatingNavBlurSigma,
                sigmaY: _floatingNavBlurSigma,
              ),
              child: Container(
                width: MainShellNavigationLayout.controlSize,
                height: MainShellNavigationLayout.controlSize,
                decoration: BoxDecoration(
                  color: colors.surface.withValues(
                    alpha: _floatingNavSurfaceOpacity,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.border.withValues(alpha: 0.65),
                  ),
                ),
                child: Icon(
                  PhosphorIconsRegular.plus,
                  color: colors.textStrong,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
