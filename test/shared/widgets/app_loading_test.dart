import 'package:bbbook/core/theme/app_theme.dart';
import 'package:bbbook/shared/widgets/app_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('로딩 오버레이는 기본적으로 아래 영역의 입력을 차단한다', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AppLoadingOverlay(
          isLoading: true,
          child: Center(
            child: TextButton(
              onPressed: () => tapCount++,
              child: const Text('버튼'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('버튼'), warnIfMissed: false);
    expect(tapCount, 0);
  });

  testWidgets('입력 차단을 끄면 전체 딤 아래의 내비게이션 입력을 전달한다', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AppLoadingOverlay(
          isLoading: true,
          blockInteraction: false,
          child: Center(
            child: TextButton(
              onPressed: () => tapCount++,
              child: const Text('뒤로가기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('뒤로가기'));
    expect(tapCount, 1);
  });
}
