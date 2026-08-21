import 'package:bbbook/features/book_note/screens/widgets/book_note_memo_sheet.dart';
import 'package:bbbook/features/book_note/screens/widgets/highlight_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('강조 버튼 탭이 텍스트 선택 영역을 죽이지 않고 강조를 적용한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showBookNoteMemoEditor(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final contentField = find.byKey(const Key('book_note_memo_content_field'));
    expect(contentField, findsOneWidget);
    await tester.enterText(contentField, 'hello world');
    await tester.pump();

    final field = tester.widget<TextField>(contentField);
    final controller = field.controller! as MemoHighlightController;
    controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(InkWell, '강조'));
    await tester.pump();

    // 버튼 탭이 TextField 포커스를 뺏어 선택 영역을 collapse시키지 않아야 한다.
    expect(controller.selection.isCollapsed, isFalse);
    expect(controller.selection.start, 0);
    expect(controller.selection.end, 5);
    expect(controller.toRaw(), '::hl[[hello]] world');

    // 강조가 반영된 상태로 한 프레임 더 렌더돼도 예외가 없어야 한다.
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
