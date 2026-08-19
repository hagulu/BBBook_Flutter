import 'package:bbbook/features/book_memo/utils/memo_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMemoHighlight', () {
    test('마크업이 없으면 그대로 평문', () {
      final parsed = parseMemoHighlight('일반 텍스트');
      expect(parsed.plainText, '일반 텍스트');
      expect(parsed.ranges, isEmpty);
    });

    test('강조 하나를 평문 + range로 분해', () {
      final parsed = parseMemoHighlight('책의 ::hl[[이 부분이 중요한 내용이다]] 그리고 다음 내용');
      expect(parsed.plainText, '책의 이 부분이 중요한 내용이다 그리고 다음 내용');
      expect(parsed.ranges, hasLength(1));
      final r = parsed.ranges.single;
      expect(parsed.plainText.substring(r.start, r.end), '이 부분이 중요한 내용이다');
    });

    test('강조 여러 개', () {
      final parsed = parseMemoHighlight('a::hl[[b]]c::hl[[d]]e');
      expect(parsed.plainText, 'abcde');
      expect(parsed.ranges, hasLength(2));
      expect(parsed.ranges[0].start, 1);
      expect(parsed.ranges[0].end, 2);
      expect(parsed.ranges[1].start, 3);
      expect(parsed.ranges[1].end, 4);
    });

    test('빈 강조 마크업은 range 없이 제거됨', () {
      final parsed = parseMemoHighlight('a::hl[[]]b');
      expect(parsed.plainText, 'ab');
      expect(parsed.ranges, isEmpty);
    });

    test('null/빈 문자열', () {
      expect(parseMemoHighlight(null).plainText, '');
      expect(parseMemoHighlight('').plainText, '');
    });
  });

  group('serializeMemoHighlight round-trip', () {
    test('parse 후 serialize하면 원본과 동일', () {
      const raw = '책의 ::hl[[이 부분이 중요한 내용이다]] 그리고 다음 내용';
      final parsed = parseMemoHighlight(raw);
      expect(serializeMemoHighlight(parsed.plainText, parsed.ranges), raw);
    });

    test('강조 여러 개 round-trip', () {
      const raw = 'a::hl[[b]]c::hl[[d]]e';
      final parsed = parseMemoHighlight(raw);
      expect(serializeMemoHighlight(parsed.plainText, parsed.ranges), raw);
    });

    test('강조 없는 평문은 그대로', () {
      expect(serializeMemoHighlight('그냥 텍스트', const []), '그냥 텍스트');
    });

    test('맞닿거나 겹치는 range는 하나로 병합', () {
      final merged = serializeMemoHighlight('abcdef', const [
        MemoHighlightRange(0, 2),
        MemoHighlightRange(2, 4),
      ]);
      expect(merged, '::hl[[abcd]]ef');
    });
  });

  group('hasMemoHighlight', () {
    test('강조가 있으면 true', () {
      expect(hasMemoHighlight('일반 ::hl[[강조]] 내용'), isTrue);
    });

    test('강조가 없으면 false', () {
      expect(hasMemoHighlight('일반 내용'), isFalse);
    });

    test('모든 강조를 해제한 뒤에는 false', () {
      // 웹 예시: 강조 해제 시 마크업만 제거하고 텍스트는 유지된다.
      const afterUnhighlight = '일반 내용 강조 내용 일반 내용';
      expect(hasMemoHighlight(afterUnhighlight), isFalse);
    });

    test('null/빈 문자열은 false', () {
      expect(hasMemoHighlight(null), isFalse);
      expect(hasMemoHighlight(''), isFalse);
    });
  });
}
