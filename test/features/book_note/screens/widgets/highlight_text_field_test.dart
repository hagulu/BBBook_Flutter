import 'package:bbbook/core/theme/app_theme.dart';
import 'package:bbbook/features/book_note/screens/widgets/highlight_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoHighlightController.fromRaw', () {
    test('마크업을 평문 + range로 복원', () {
      final controller = MemoHighlightController.fromRaw(
        '책의 ::hl[[이 부분이 중요한 내용이다]] 그리고 다음 내용',
      );
      expect(controller.text, '책의 이 부분이 중요한 내용이다 그리고 다음 내용');
      expect(controller.hasHighlight, isTrue);
      expect(controller.toRaw(), '책의 ::hl[[이 부분이 중요한 내용이다]] 그리고 다음 내용');
    });

    test('마크업이 없으면 강조 없음', () {
      final controller = MemoHighlightController.fromRaw('그냥 텍스트');
      expect(controller.hasHighlight, isFalse);
      expect(controller.toRaw(), '그냥 텍스트');
    });
  });

  group('선택 영역 기반 토글', () {
    test('일반 텍스트 선택 + 토글 → 강조 추가', () {
      final controller = MemoHighlightController(plainText: 'hello world');
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      controller.toggleAtSelection();
      expect(controller.toRaw(), '::hl[[hello]] world');
      expect(controller.hasHighlight, isTrue);
    });

    test('강조된 텍스트 선택 + 토글 → 강조 해제(텍스트는 유지)', () {
      final controller = MemoHighlightController.fromRaw('::hl[[hello]] world');
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      controller.toggleAtSelection();
      expect(controller.toRaw(), 'hello world');
      expect(controller.hasHighlight, isFalse);
    });

    test('스펙 예시: 강조 덩어리 선택 해제 시 다른 강조 없으면 isImportant=false', () {
      final controller = MemoHighlightController.fromRaw(
        '책의 ::hl[[이 부분이 중요한 내용이다]] 그리고 다음 내용',
      );
      final start = controller.text.indexOf('이 부분이');
      final end = start + '이 부분이 중요한 내용이다'.length;
      controller.selection = TextSelection(baseOffset: start, extentOffset: end);
      controller.toggleAtSelection();
      expect(controller.text, '책의 이 부분이 중요한 내용이다 그리고 다음 내용');
      expect(controller.hasHighlight, isFalse);
    });
  });

  group('선택 영역을 타이핑으로 교체(토글 버튼을 거치지 않음)', () {
    test('강조된 선택 영역 전체를 교체하면 새 텍스트도 강조 유지', () {
      final controller = MemoHighlightController.fromRaw('abc::hl[[hello]]def');
      final start = controller.text.indexOf('hello');
      final end = start + 'hello'.length;
      controller.selection = TextSelection(baseOffset: start, extentOffset: end);
      expect(controller.isActiveAtSelection, isTrue);

      controller.value = controller.value.copyWith(
        text: 'abcworlddef',
        selection: TextSelection.collapsed(offset: start + 'world'.length),
      );
      expect(controller.toRaw(), 'abc::hl[[world]]def');
    });

    test('일부만 강조된 선택 영역을 교체하면 새 텍스트는 강조되지 않는다', () {
      // "cd"만 강조, 선택은 "bcde"(강조 없는 b, e가 섞임).
      final controller = MemoHighlightController.fromRaw('ab::hl[[cd]]ef');
      final start = controller.text.indexOf('bcde');
      final end = start + 'bcde'.length;
      controller.selection = TextSelection(baseOffset: start, extentOffset: end);
      expect(controller.isActiveAtSelection, isFalse); // 전체 커버리지 아니므로 비활성

      controller.value = controller.value.copyWith(
        text: 'aXf',
        selection: TextSelection.collapsed(offset: start + 1),
      );
      expect(controller.toRaw(), 'aXf');
      expect(controller.hasHighlight, isFalse);
    });

    test('강조 없는 선택 영역을 교체하면 그대로 평문(회귀 확인)', () {
      final controller = MemoHighlightController(plainText: 'hello world');
      controller.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
      controller.value = controller.value.copyWith(
        text: 'hello there',
        selection: const TextSelection.collapsed(offset: 11),
      );
      expect(controller.toRaw(), 'hello there');
    });
  });

  group('buildTextSpan', () {
    testWidgets('강조와 조합 중 밑줄이 겹치는 구간은 둘 다 적용된다', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      final controller = MemoHighlightController.fromRaw('::hl[[abc]]def');
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 1, end: 2), // 'b' 조합 중, 강조 안쪽
      );

      final span = controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(),
        withComposing: true,
      );
      expect(span.toPlainText(), 'abcdef');

      var found = false;
      void visit(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text == 'b') {
            expect(s.style?.decoration, TextDecoration.underline);
            expect(s.style?.backgroundColor, AppColors.highlightGoldSurface);
            found = true;
          }
          s.children?.forEach(visit);
        }
      }

      visit(span);
      expect(found, isTrue);
    });
  });

  group('커서 기반 토글(선택 영역 없음)', () {
    test('일반 텍스트 위치에서 토글 ON 후 타이핑하면 강조됨', () {
      final controller = MemoHighlightController(plainText: 'abc');
      controller.selection = const TextSelection.collapsed(offset: 3);
      controller.toggleAtSelection();
      expect(controller.isActiveAtSelection, isTrue);

      controller.value = controller.value.copyWith(
        text: 'abcd',
        selection: const TextSelection.collapsed(offset: 4),
      );
      expect(controller.toRaw(), 'abc::hl[[d]]');
    });

    test('토글 OFF 상태에서 타이핑하면 일반 텍스트', () {
      final controller = MemoHighlightController(plainText: 'abc');
      controller.selection = const TextSelection.collapsed(offset: 3);
      controller.value = controller.value.copyWith(
        text: 'abcd',
        selection: const TextSelection.collapsed(offset: 4),
      );
      expect(controller.toRaw(), 'abcd');
      expect(controller.hasHighlight, isFalse);
    });

    test('커서가 강조 영역 안이면 버튼이 활성으로 표시', () {
      final controller = MemoHighlightController.fromRaw('a::hl[[bcd]]e');
      controller.selection = const TextSelection.collapsed(offset: 2);
      expect(controller.isActiveAtSelection, isTrue);
    });

    test('커서가 강조 "안쪽"이면 토글이 완전히 막힌다(아무 일도 안 함)', () {
      final controller = MemoHighlightController.fromRaw('a::hl[[bcd]]e');
      controller.selection = const TextSelection.collapsed(offset: 2); // a[b|cd]e
      expect(controller.isBlockedAtSelection, isTrue);
      controller.toggleAtSelection();
      // 기존 강조 데이터도, 활성 표시도 전혀 바뀌지 않는다.
      expect(controller.toRaw(), 'a::hl[[bcd]]e');
      expect(controller.isActiveAtSelection, isTrue);
    });

    test('강조 맨 뒤 경계에서만 토글이 막히지 않는다(맨 앞은 막힘)', () {
      final controller = MemoHighlightController.fromRaw('a::hl[[bcd]]e');
      controller.selection = const TextSelection.collapsed(offset: 1); // 맨 앞(a|bcd)
      expect(controller.isBlockedAtSelection, isTrue);
      controller.selection = const TextSelection.collapsed(offset: 4); // 맨 뒤(bcd|e)
      expect(controller.isBlockedAtSelection, isFalse);
    });

    test('핵심 시나리오: 강조 ON→타이핑→OFF→타이핑하면 끈 지점에서 바로 끊긴다', () {
      final controller = MemoHighlightController(plainText: '');
      controller.selection = const TextSelection.collapsed(offset: 0);
      controller.toggleAtSelection(); // 강조 ON
      expect(controller.isActiveAtSelection, isTrue);

      controller.value = controller.value.copyWith(
        text: 'hello',
        selection: const TextSelection.collapsed(offset: 5),
      );
      expect(controller.toRaw(), '::hl[[hello]]');
      expect(controller.isActiveAtSelection, isTrue); // 커서가 강조 뒤끝이라 상속 활성

      // 실제로 강조된 글자 바로 뒤에서 끄므로 경계 공백이 자동으로 삽입된다.
      controller.toggleAtSelection();
      expect(controller.text, 'hello ');
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
      expect(controller.isActiveAtSelection, isFalse);

      controller.value = controller.value.copyWith(
        text: 'hello world',
        selection: const TextSelection.collapsed(offset: 11),
      );
      expect(controller.toRaw(), '::hl[[hello]] world');
    });

    test('타이핑 전에 켰다가 바로 끄면 아무것도 강조되지 않는다(가장 앞에서 끊기)', () {
      final controller = MemoHighlightController(plainText: 'abc');
      controller.selection = const TextSelection.collapsed(offset: 3);
      controller.toggleAtSelection(); // ON
      controller.toggleAtSelection(); // 곧바로 OFF

      controller.value = controller.value.copyWith(
        text: 'abcd',
        selection: const TextSelection.collapsed(offset: 4),
      );
      expect(controller.toRaw(), 'abcd');
      expect(controller.hasHighlight, isFalse);
    });

    test('커서 이동(텍스트 불변)하면 세션 오버라이드가 초기화됨', () {
      final controller = MemoHighlightController(plainText: 'ab cd');
      controller.selection = const TextSelection.collapsed(offset: 2);
      controller.toggleAtSelection(); // ON 오버라이드
      expect(controller.isActiveAtSelection, isTrue);

      // 텍스트 변경 없이 커서만 이동.
      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 4),
      );
      expect(controller.isActiveAtSelection, isFalse);
    });

    test('오프셋은 그대로인데 affinity 등 부가 정보만 바뀌면 세션 오버라이드 유지', () {
      // IME가 음절을 완성하면서 텍스트 변경 없이 커서 affinity만 갱신하는
      // 이벤트를 보낼 수 있다. 이런 이벤트로 세션 오버라이드가 풀리면
      // "핵심 시나리오" 테스트가 검증하는 ON→타이핑→OFF 흐름이 깨진다.
      final controller = MemoHighlightController(plainText: 'abc');
      controller.selection = const TextSelection.collapsed(offset: 3);
      controller.toggleAtSelection(); // ON
      expect(controller.isActiveAtSelection, isTrue);

      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(
          offset: 3,
          affinity: TextAffinity.upstream,
        ),
      );
      expect(controller.isActiveAtSelection, isTrue);
    });

    test('강조 영역 중간에 타이핑하면 강조가 자동으로 늘어남', () {
      final controller = MemoHighlightController.fromRaw('::hl[[abd]]');
      controller.selection = const TextSelection.collapsed(offset: 2); // ab|d
      controller.value = controller.value.copyWith(
        text: 'abcd',
        selection: const TextSelection.collapsed(offset: 3),
      );
      expect(controller.toRaw(), '::hl[[abcd]]');
    });
  });

  group('한글 IME 조합 시퀀스', () {
    test('강조 ON 상태에서 자모 조합 중에도 강조 유지 (ㄱ→가→갈)', () {
      final controller = MemoHighlightController(plainText: 'abc');
      controller.selection = const TextSelection.collapsed(offset: 3);
      controller.toggleAtSelection(); // 강조 ON

      controller.value = controller.value.copyWith(
        text: 'abcㄱ',
        selection: const TextSelection.collapsed(offset: 4),
      );
      expect(controller.toRaw(), 'abc::hl[[ㄱ]]');

      // IME가 마지막 글자를 완성된 조합으로 교체(delete+insert).
      controller.value = controller.value.copyWith(
        text: 'abc가',
        selection: const TextSelection.collapsed(offset: 4),
      );
      expect(controller.toRaw(), 'abc::hl[[가]]');

      controller.value = controller.value.copyWith(
        text: 'abc갈',
        selection: const TextSelection.collapsed(offset: 4),
      );
      expect(controller.toRaw(), 'abc::hl[[갈]]');
    });

    test('기존 강조 끝에서 이어 타이핑(상속) 중 자모 조합해도 강조 유지', () {
      final controller = MemoHighlightController.fromRaw('::hl[[가나]]');
      controller.selection = const TextSelection.collapsed(offset: 2); // 강조 끝
      expect(controller.isActiveAtSelection, isTrue);

      controller.value = controller.value.copyWith(
        text: '가나ㄷ',
        selection: const TextSelection.collapsed(offset: 3),
      );
      controller.value = controller.value.copyWith(
        text: '가나다',
        selection: const TextSelection.collapsed(offset: 3),
      );
      expect(controller.toRaw(), '::hl[[가나다]]');
    });

    test(
      '조합 중 받침이 다음 음절 초성으로 넘어가 글자 수가 줄어드는 diff에서도 '
      '조합 시작 시점의 강조가 유지된다',
      () {
        // 'b'만 강조된 상태에서 이어서(상속) 조합을 시작하면 강조 ON으로
        // 시작된다. 조합 도중 그 'b'가 다음 음절에 흡수되며 글자 수가
        // 3글자→2글자로 줄어드는 delete+insert가 발생해도(받침이 다음 음절
        // 초성으로 넘어가는 재음절화와 같은 모양) 조합 세션 시작 때 정한
        // 강조가 그대로 유지돼야 한다. 세션 스냅샷이 없으면 이 시점에 diff의
        // 시작 위치 바로 앞 글자가 강조 없는 'a'로 바뀌어 있어 강조가 조용히
        // 사라진다.
        final controller = MemoHighlightController.fromRaw('a::hl[[b]]');
        controller.selection = const TextSelection.collapsed(offset: 2);
        expect(controller.isActiveAtSelection, isTrue); // 상속으로 활성

        controller.value = controller.value.copyWith(
          text: 'abㄱ',
          selection: const TextSelection.collapsed(offset: 3),
          composing: const TextRange(start: 2, end: 3),
        );
        expect(controller.toRaw(), 'a::hl[[bㄱ]]');

        controller.value = controller.value.copyWith(
          text: 'a간',
          selection: const TextSelection.collapsed(offset: 2),
          composing: const TextRange(start: 1, end: 2),
        );
        expect(controller.toRaw(), 'a::hl[[간]]');
      },
    );

    test('조합 중에 강조를 끄면 실제 공백이 삽입되며 경계가 확정된다', () {
      final controller = MemoHighlightController(plainText: '');
      controller.selection = const TextSelection.collapsed(offset: 0);
      controller.toggleAtSelection(); // 강조 ON

      controller.value = controller.value.copyWith(
        text: 'ㄱ',
        selection: const TextSelection.collapsed(offset: 1),
        composing: const TextRange(start: 0, end: 1),
      );
      expect(controller.toRaw(), '::hl[[ㄱ]]');

      // 조합이 아직 안 끝난 채로(composing 유효) 강조를 끈다 — 실제로 강조된
      // 'ㄱ' 바로 뒤이므로 공백이 삽입돼 조합 대상 텍스트 자체가 바뀐다.
      controller.toggleAtSelection();
      expect(controller.text, 'ㄱ ');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
      expect(controller.isActiveAtSelection, isFalse);

      // 앞서 강조된 'ㄱ'은 그대로 남고, 공백 뒤로 새로 시작하는 조합은
      // 강조되지 않는다.
      controller.value = controller.value.copyWith(
        text: 'ㄱ 가',
        selection: const TextSelection.collapsed(offset: 3),
        composing: const TextRange(start: 2, end: 3),
      );
      expect(controller.toRaw(), '::hl[[ㄱ]] 가');
    });
  });

  group('타입 전환 시 강조 초기화', () {
    test('clearHighlights는 텍스트는 유지하고 강조만 제거', () {
      final controller = MemoHighlightController.fromRaw('::hl[[hello]] world');
      controller.clearHighlights();
      expect(controller.text, 'hello world');
      expect(controller.hasHighlight, isFalse);
      expect(controller.toRaw(), 'hello world');
    });
  });
}
