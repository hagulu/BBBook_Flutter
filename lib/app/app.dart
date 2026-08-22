import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

class BBBookApp extends ConsumerWidget {
  const BBBookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: '책책책',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
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
