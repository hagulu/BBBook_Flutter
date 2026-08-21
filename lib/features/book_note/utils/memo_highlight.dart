/// 메모 강조(하이라이트) 마크업 유틸.
///
/// 웹과 동일한 `::hl[[텍스트]]` 규칙을 그대로 사용한다. 강조 위치/범위는
/// [content] 문자열 안에 이 마크업으로만 저장하고, `is_important`는 강조가
/// 하나라도 있는지를 나타내는 파생값으로만 취급한다.
library;

/// 강조 영역 하나. [start]/[end]는 마크업이 제거된 평문 기준 오프셋이며
/// [end]는 배타적(exclusive)이다.
class MemoHighlightRange {
  const MemoHighlightRange(this.start, this.end);

  final int start;
  final int end;
}

/// [ParsedMemoHighlight.plainText]는 `::hl[[]]` 마크업이 제거된, 사용자에게
/// 보여줄 평문이다. [ranges]는 그 평문 기준 강조 오프셋 목록(정렬됨).
class ParsedMemoHighlight {
  const ParsedMemoHighlight({required this.plainText, required this.ranges});

  final String plainText;
  final List<MemoHighlightRange> ranges;
}

final RegExp _highlightPattern = RegExp(r'::hl\[\[(.*?)\]\]', dotAll: true);

/// [raw]를 평문 + 강조 오프셋 목록으로 분해한다.
ParsedMemoHighlight parseMemoHighlight(String? raw) {
  if (raw == null || raw.isEmpty) {
    return const ParsedMemoHighlight(plainText: '', ranges: []);
  }
  final buffer = StringBuffer();
  final ranges = <MemoHighlightRange>[];
  var offset = 0;
  for (final match in _highlightPattern.allMatches(raw)) {
    if (match.start > offset) {
      buffer.write(raw.substring(offset, match.start));
    }
    final inner = match.group(1)!;
    if (inner.isNotEmpty) {
      final start = buffer.length;
      buffer.write(inner);
      ranges.add(MemoHighlightRange(start, buffer.length));
    }
    offset = match.end;
  }
  if (offset < raw.length) {
    buffer.write(raw.substring(offset));
  }
  return ParsedMemoHighlight(plainText: buffer.toString(), ranges: ranges);
}

/// [plainText]와 [ranges]를 다시 `::hl[[]]` 마크업 문자열로 합친다. 겹치거나
/// 맞닿은 영역은 하나로 병합한다.
String serializeMemoHighlight(
  String plainText,
  List<MemoHighlightRange> ranges,
) {
  final nonEmpty = ranges.where((r) => r.start < r.end).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  if (nonEmpty.isEmpty) return plainText;

  final merged = <MemoHighlightRange>[];
  for (final r in nonEmpty) {
    if (merged.isNotEmpty && r.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add(
        MemoHighlightRange(last.start, r.end > last.end ? r.end : last.end),
      );
    } else {
      merged.add(r);
    }
  }

  final buffer = StringBuffer();
  var offset = 0;
  for (final r in merged) {
    if (r.start > offset) buffer.write(plainText.substring(offset, r.start));
    buffer
      ..write('::hl[[')
      ..write(plainText.substring(r.start, r.end))
      ..write(']]');
    offset = r.end;
  }
  if (offset < plainText.length) buffer.write(plainText.substring(offset));
  return buffer.toString();
}

/// [content]에 강조 영역이 하나라도 있으면 true. `is_important` 파생 규칙의
/// 단일 기준이다.
bool hasMemoHighlight(String? content) =>
    parseMemoHighlight(content).ranges.isNotEmpty;

/// 마크업을 제거한 평문만 필요할 때 사용한다(예: PHOTO 설명 저장 시 방어적
/// strip).
String stripMemoHighlightMarkup(String? raw) => parseMemoHighlight(raw).plainText;
