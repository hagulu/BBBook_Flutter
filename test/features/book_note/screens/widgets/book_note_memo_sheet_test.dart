import 'package:bbbook/core/policy/attachment_limit_policy.dart';
import 'package:bbbook/core/theme/app_theme.dart';
import 'package:bbbook/features/book_note/screens/widgets/book_note_memo_sheet.dart';
import 'package:bbbook/features/book_note/screens/widgets/highlight_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _policy = AttachmentLimitPolicy.defaultPolicy;

void main() {
  testWidgets('강조 버튼 탭이 텍스트 선택 영역을 죽이지 않고 강조를 적용한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // 화면이 `AppColors.of`로 색상 토큰을 읽으므로 `AppPalette`가 실린
        // 앱 테마로 띄운다(맨 `ThemeData`에는 확장이 없어 assert에 걸린다).
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showBookNoteMemoEditor(
                  context,
                  attachmentLimitPolicy: _policy,
                  currentImageMemoCount: 0,
                ),
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

  testWidgets('노트 이미지 한도에 도달하면 사진 타입을 선택해도 사진 편집 화면으로 전환되지 않는다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showBookNoteMemoEditor(
                  context,
                  attachmentLimitPolicy: _policy,
                  // 이미 노트 이미지 한도(3개)에 도달한 상태, 편집 중인
                  // 메모 자체는 이미지가 없던 새 메모(교체가 아님).
                  currentImageMemoCount: _policy.noteImageLimit,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('사진'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text(_policy.noteImageLimitMessage), findsOneWidget);
    // 사진 타입으로 전환되지 않았으므로 텍스트 메모 입력 힌트가 그대로다.
    expect(find.text('기록할 내용을 입력하세요.'), findsOneWidget);
    expect(find.text('사진에 대한 설명이나 기억을 남겨보세요.'), findsNothing);
  });
}
