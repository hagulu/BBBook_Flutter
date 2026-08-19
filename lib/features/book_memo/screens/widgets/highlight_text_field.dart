import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../utils/memo_highlight.dart';

/// 텍스트 메모 조각 본문에 웹과 동일한 `::hl[[]]` 강조를 지원하는
/// [TextEditingController].
///
/// 사용자에게는 마크업 없는 평문만 보이고([text]), 강조 위치는 [highlights]로
/// 별도 관리한다. 저장 시 [toRaw]로 다시 `::hl[[]]` 마크업 문자열을 만든다.
///
/// **강조 상태 판단**: 커서 바로 앞 글자 기준([isHighlightedAt], 오프셋 0이면
/// 뒤 글자). 경계에서 타이핑이 강조를 잇는지는 이 규칙과 [_shiftForInsertion]의
/// 경계 처리(경계에서 시작하는 range는 삽입 위치와 함께 밀리고, 경계에서
/// 끝나는 range는 밀리지 않음)로 결정된다.
///
/// **토글 버튼**: 커서만 있을 때 강조 덩어리의 맨 뒤 경계에서만 동작하고, 그
/// 앞쪽/안쪽에서는 아무 일도 하지 않는다([isBlockedAtSelection]). 커서
/// 위치로 기존 강조를 지우거나 나누지 않으며, "다음 입력을 강조할지" 세션
/// 플래그만 뒤집는다. 실제로 강조된 글자 바로 뒤에서 끌 때는 공백을 하나
/// 실제로 삽입해 경계를 확정한다. 전체 정책 문서:
/// `docs/policies/memo-highlight-toggle.md`.
///
/// **한글 IME 조합**: 재음절화나 조합 중 백스페이스는 한 글자 교체가 아닌
/// 임의의 삭제+삽입으로 들어올 수 있어, keystroke마다 강조 여부를 새로
/// 판단하면 어긋난다. 조합 세션 하나에서 쓸 강조 여부를 세션 시작 때 한 번만
/// 정해 세션이 끝날 때까지 고정한다([_composingHighlightSnapshot]).
class MemoHighlightController extends TextEditingController {
  MemoHighlightController({String? plainText})
    : _highlights = const [],
      super(text: plainText ?? '');

  factory MemoHighlightController.fromRaw(String? raw) {
    final parsed = parseMemoHighlight(raw);
    final controller = MemoHighlightController(plainText: parsed.plainText);
    controller._highlights = parsed.ranges;
    return controller;
  }

  List<MemoHighlightRange> _highlights;

  /// 명시적으로 켜졌거나(true) 꺼진(false) "다음 입력에 적용할 강조" 세션
  /// 오버라이드. null이면 커서 위치의 기존 강조 여부를 그대로 상속한다.
  /// 커서만 이동하는(텍스트 변경 없는) 값 변경에서 초기화된다.
  bool? _typingHighlightOn;

  /// 한글 IME 조합 세션 하나에서 쓸 강조 여부 스냅샷(클래스 문서 참고).
  bool? _composingHighlightSnapshot;

  List<MemoHighlightRange> get highlights => List.unmodifiable(_highlights);

  bool get hasHighlight => _highlights.isNotEmpty;

  String toRaw() => serializeMemoHighlight(text, _highlights);

  /// [_typingHighlightOn]과 [_composingHighlightSnapshot]은 항상 함께
  /// 리셋해야 한다 — 세션 오버라이드만 지우고 조합 스냅샷을 남겨두면, 아직
  /// 안 끝난 조합 세션이 방금 리셋된 오버라이드 대신 옛 스냅샷 값을 계속
  /// 쓰게 된다.
  void _resetTypingSession() {
    _typingHighlightOn = null;
    _composingHighlightSnapshot = null;
  }

  /// PHOTO 타입으로 전환하는 등, 강조를 완전히 비울 때 사용한다. 텍스트 자체는
  /// 건드리지 않는다.
  void clearHighlights() {
    if (_highlights.isEmpty &&
        _typingHighlightOn == null &&
        _composingHighlightSnapshot == null) {
      return;
    }
    _highlights = const [];
    _resetTypingSession();
    notifyListeners();
  }

  bool isHighlightedAt(int offset) {
    if (text.isEmpty) return false;
    final checkOffset = offset > 0 ? offset - 1 : offset;
    for (final r in _highlights) {
      if (checkOffset >= r.start && checkOffset < r.end) return true;
    }
    return false;
  }

  /// 강조 버튼의 활성 표시 상태. 선택 영역이 있으면 "선택 전체가 강조돼
  /// 있는가", 커서만 있으면 세션 오버라이드 우선, 없으면 상속 상태(커서 바로
  /// 앞 글자가 강조돼 있는가).
  bool get isActiveAtSelection {
    final sel = selection;
    if (!sel.isValid) return false;
    if (!sel.isCollapsed) {
      return _isRangeFullyHighlighted(sel.start, sel.end);
    }
    return _typingHighlightOn ?? isHighlightedAt(sel.baseOffset);
  }

  /// 커서가 강조 덩어리의 맨 뒤 경계가 아닌, 그 앞쪽(시작 지점 포함) 어디에
  /// 있어 토글이 아무 동작도 하지 않는 상태인지. 토글이 살아있는 곳은 강조와
  /// 무관한 일반 위치와, 강조 덩어리의 맨 뒤(그 지점에서 잘라내는 용도)뿐이다.
  /// 선택 영역이 있을 때는 항상 false(선택 토글은 항상 가능).
  bool get isBlockedAtSelection {
    final sel = selection;
    if (!sel.isValid || !sel.isCollapsed) return false;
    return _blocksToggle(sel.baseOffset);
  }

  bool _blocksToggle(int pos) {
    for (final r in _highlights) {
      if (pos >= r.start && pos < r.end) return true;
    }
    return false;
  }

  /// 강조 버튼을 눌렀을 때의 동작.
  ///
  /// 선택 영역이 있으면 그 영역을 그대로 강조/해제한다.
  ///
  /// 커서만 있을 때, 강조 덩어리의 맨 뒤가 아닌 앞쪽/안쪽([isBlockedAtSelection])
  /// 이면 아무 일도 하지 않는다 — 커서 위치로 기존 강조를 지우거나 나누는
  /// 기능은 없다. 그 외에는 **이미 저장된 강조 데이터는 건드리지 않고**,
  /// "다음 입력을 강조할지" 세션 플래그만 뒤집는다(현재 표시 상태의 반대로).
  ///
  /// 그중 **실제로 강조된 글자 바로 뒤에서 끌 때만** 공백을 하나 실제로
  /// 삽입해 경계를 확정 짓는다(아직 아무것도 안 쓴 채 켰다 바로 끄는 경우는
  /// 삽입하지 않음). 텍스트가 실제로 바뀌므로, 마침 한글 조합 중이었어도
  /// 조합 대상이 어긋나며 자연스럽게 끊긴다. 자세한 정책은
  /// `docs/policies/memo-highlight-toggle.md` 참고.
  void toggleAtSelection() {
    final sel = selection;
    if (!sel.isValid) return;
    if (!sel.isCollapsed) {
      final start = sel.start;
      final end = sel.end;
      _highlights = _isRangeFullyHighlighted(start, end)
          ? _subtractRange(_highlights, start, end)
          : _addRange(_highlights, start, end);
      _resetTypingSession();
      notifyListeners();
      return;
    }
    final pos = sel.baseOffset;
    if (_blocksToggle(pos)) return;
    final wasHighlightedHere = isHighlightedAt(pos);
    final currentlyActive = _typingHighlightOn ?? wasHighlightedHere;
    _typingHighlightOn = !currentlyActive;
    _composingHighlightSnapshot = null;
    if (currentlyActive && wasHighlightedHere) {
      value = TextEditingValue(
        text: text.replaceRange(pos, pos, ' '),
        selection: TextSelection.collapsed(offset: pos + 1),
      );
      return;
    }
    notifyListeners();
  }

  bool _isRangeFullyHighlighted(int start, int end) {
    if (start >= end) return false;
    var cursor = start;
    for (final r in _highlights) {
      if (r.end <= cursor) continue;
      if (r.start > cursor) return false;
      cursor = r.end;
      if (cursor >= end) return true;
    }
    return cursor >= end;
  }

  @override
  set value(TextEditingValue newValue) {
    final oldValue = value;
    if (newValue.text != oldValue.text) {
      _applyTextDiff(oldValue, newValue);
    } else if (newValue.selection.baseOffset != oldValue.selection.baseOffset ||
        newValue.selection.extentOffset != oldValue.selection.extentOffset) {
      // 오프셋이 실제로 바뀐 커서 이동/선택 변경에서만 세션을 초기화한다.
      // 텍스트가 그대로인 채 affinity 등 부가 정보만 바뀌는 IME 조합 중간
      // 이벤트(예: 음절 완성 시 커서 방향성 갱신)로 초기화되면, 마지막에
      // 입력한 글자가 강조를 놓치는 문제로 이어진다.
      _resetTypingSession();
    }
    super.value = newValue;
  }

  void _applyTextDiff(TextEditingValue oldValue, TextEditingValue newValue) {
    final oldText = oldValue.text;
    final newText = newValue.text;
    var prefix = 0;
    final maxPrefix = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    while (prefix < maxPrefix && oldText[prefix] == newText[prefix]) {
      prefix++;
    }
    var suffix = 0;
    final maxSuffix = maxPrefix - prefix;
    while (suffix < maxSuffix &&
        oldText[oldText.length - 1 - suffix] ==
            newText[newText.length - 1 - suffix]) {
      suffix++;
    }
    final deleteStart = prefix;
    final deleteEnd = oldText.length - suffix;
    final insertEnd = newText.length - suffix;
    final insertedLength = insertEnd - prefix;

    // 같은 조합 세션(oldValue가 이미 조합 중이었음) 안이면, 이번 delete+insert가
    // 아무리 이상하게 생겼어도(재음절화, 조합 중 백스페이스 등) 세션 시작 때
    // 정한 강조 여부를 그대로 쓴다. 새 세션이면 오버라이드를 우선하고, 없으면
    // 커서 위치를 본다 — 단, 선택 영역을 교체하는 입력(deleteEnd > deleteStart)
    // 이면 "삽입 위치 앞 글자"가 아니라 "교체되는 범위 전체가 강조였는가"를
    // 본다. 커서 삽입과 달리 교체 대상 자체가 신호이고, 강조 버튼의 활성
    // 표시([isActiveAtSelection])와 같은 기준(전체 커버리지)을 써서 "버튼이
    // 활성으로 보이던 선택을 교체하면 그대로 강조가 유지된다"는 게 일관되게
    // 성립하게 한다.
    final bool pendingHighlight;
    if (oldValue.composing.isValid && _composingHighlightSnapshot != null) {
      pendingHighlight = _composingHighlightSnapshot!;
    } else if (_typingHighlightOn != null) {
      pendingHighlight = _typingHighlightOn!;
    } else if (deleteEnd > deleteStart) {
      pendingHighlight = _isRangeFullyHighlighted(deleteStart, deleteEnd);
    } else {
      pendingHighlight = isHighlightedAt(deleteStart);
    }
    _composingHighlightSnapshot = newValue.composing.isValid
        ? pendingHighlight
        : null;

    var highlights = _highlights;
    if (deleteEnd > deleteStart) {
      highlights = _shiftForDeletion(highlights, deleteStart, deleteEnd);
    }
    if (insertedLength > 0) {
      highlights = _shiftForInsertion(highlights, deleteStart, insertedLength);
      if (pendingHighlight) {
        highlights = _addRange(
          highlights,
          deleteStart,
          deleteStart + insertedLength,
        );
      }
    }
    _highlights = highlights;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_highlights.isEmpty) {
      // 강조가 없으면 기본 구현에 그대로 맡긴다 — 조합 중 밑줄 등 플랫폼 기본
      // 표시를 우리가 따로 흉내 낼 필요가 없다.
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final composingRange = withComposing && value.isComposingRangeValid
        ? value.composing
        : null;
    final highlightStyle = (style ?? const TextStyle()).copyWith(
      backgroundColor: AppColors.highlightGoldSurface,
    );
    // 강조 span과 조합 중 span이 서로 걸칠 수 있으므로, 두 범위의 경계를 모두
    // 모아 쪼갠 구간마다 강조/밑줄을 독립적으로 합성한다.
    final breakpoints = <int>{0, text.length};
    for (final r in _highlights) {
      breakpoints
        ..add(r.start)
        ..add(r.end);
    }
    if (composingRange != null) {
      breakpoints
        ..add(composingRange.start)
        ..add(composingRange.end);
    }
    final sorted = breakpoints.toList()..sort();
    final spans = <TextSpan>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final start = sorted[i];
      final end = sorted[i + 1];
      if (start >= end) continue;
      final isComposing =
          composingRange != null &&
          start >= composingRange.start &&
          end <= composingRange.end;
      var segmentStyle = _rangeIsHighlighted(start, end)
          ? highlightStyle
          : (style ?? const TextStyle());
      if (isComposing) {
        segmentStyle = segmentStyle.merge(
          const TextStyle(decoration: TextDecoration.underline),
        );
      }
      spans.add(TextSpan(text: text.substring(start, end), style: segmentStyle));
    }
    return TextSpan(style: style, children: spans);
  }

  bool _rangeIsHighlighted(int start, int end) {
    for (final r in _highlights) {
      if (start >= r.start && end <= r.end) return true;
    }
    return false;
  }
}

List<MemoHighlightRange> _mergeSorted(List<MemoHighlightRange> ranges) {
  final sorted = ranges.where((r) => r.start < r.end).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final merged = <MemoHighlightRange>[];
  for (final r in sorted) {
    if (merged.isNotEmpty && r.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add(
        MemoHighlightRange(last.start, r.end > last.end ? r.end : last.end),
      );
    } else {
      merged.add(r);
    }
  }
  return merged;
}

List<MemoHighlightRange> _addRange(
  List<MemoHighlightRange> ranges,
  int start,
  int end,
) {
  if (start >= end) return ranges;
  return _mergeSorted([...ranges, MemoHighlightRange(start, end)]);
}

List<MemoHighlightRange> _subtractRange(
  List<MemoHighlightRange> ranges,
  int start,
  int end,
) {
  final result = <MemoHighlightRange>[];
  for (final r in ranges) {
    if (r.end <= start || r.start >= end) {
      result.add(r);
      continue;
    }
    if (r.start < start) result.add(MemoHighlightRange(r.start, start));
    if (r.end > end) result.add(MemoHighlightRange(end, r.end));
  }
  return result;
}

/// [start, end) 삭제에 맞춰 range를 잘라내고 뒤쪽을 당긴다. 삭제로 인해
/// 인접해진 range는 [_mergeSorted]가 하나로 합친다.
List<MemoHighlightRange> _shiftForDeletion(
  List<MemoHighlightRange> ranges,
  int start,
  int end,
) {
  final len = end - start;
  final result = <MemoHighlightRange>[];
  for (final r in ranges) {
    int s;
    int e;
    if (r.start <= start) {
      s = r.start;
    } else if (r.start >= end) {
      s = r.start - len;
    } else {
      s = start;
    }
    if (r.end <= start) {
      e = r.end;
    } else if (r.end >= end) {
      e = r.end - len;
    } else {
      e = start;
    }
    if (s < e) result.add(MemoHighlightRange(s, e));
  }
  return _mergeSorted(result);
}

/// [at] 위치에 [length]만큼 삽입될 때 range 경계를 옮긴다. 경계가 정확히
/// [at]에서 시작하는 range는 삽입 위치와 함께 밀려 새 텍스트를 포함하지 않고,
/// range 안쪽(start < at < end)에 삽입되면 range가 늘어나 새 텍스트를 포함한다.
List<MemoHighlightRange> _shiftForInsertion(
  List<MemoHighlightRange> ranges,
  int at,
  int length,
) {
  return ranges
      .map(
        (r) => MemoHighlightRange(
          r.start >= at ? r.start + length : r.start,
          r.end > at ? r.end + length : r.end,
        ),
      )
      .toList();
}
