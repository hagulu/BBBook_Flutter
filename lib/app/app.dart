import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_mode_provider.dart';
import '../features/external_record_import/widgets/external_import_share_coordinator.dart';
import 'router.dart';

final _lightTheme = buildAppTheme();
final _darkTheme = buildAppTheme(brightness: Brightness.dark);

class BBBookApp extends ConsumerWidget {
  const BBBookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: '북꾸러미',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: ref.watch(themeModeProvider),
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        final iconBrightness = brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarBrightness: brightness,
            statusBarIconBrightness: iconBrightness,
            systemNavigationBarColor: AppColors.of(context).pageBackground,
            systemNavigationBarIconBrightness: iconBrightness,
          ),
          child: ExternalImportShareCoordinator(
            navigatorKey: rootNavigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      // 한국어 전용 서비스라 로케일을 고정한다 — 이게 없으면
      // MaterialLocalizations가 영어로 떨어져, 날짜 선택 등에서 화면에 보이는
      // 한글 표시와 스크린 리더 안내(요일·월 포맷)가 서로 달라진다.
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: [
        ...GlobalMaterialLocalizations.delegates,
        FlutterQuillLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
