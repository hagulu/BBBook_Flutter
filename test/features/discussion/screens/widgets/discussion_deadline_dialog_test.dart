import 'package:bbbook/core/theme/app_theme.dart';
import 'package:bbbook/features/discussion/screens/widgets/discussion_deadline_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('마감일 저장이 징계로 거부되면 이유를 시트에서 안내한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDiscussionDeadlineDialog(
                context,
                initialClosesAt: null,
                onSave: (_) async => '징계 기간에는 마감일을 수정할 수 없습니다.',
              ),
              child: const Text('마감일 열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('마감일 열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('징계 기간에는 마감일을 수정할 수 없습니다.'), findsOneWidget);
    expect(find.text('마감일 설정/수정'), findsOneWidget);
  });
}
