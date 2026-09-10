import 'dart:convert';

import '../../book_note/utils/memo_highlight.dart';
import '../../book_reflection/services/book_reflection_content_adapter.dart';

String htmlEscape(Object? value) => const HtmlEscape()
    .convert(value?.toString() ?? '')
    .replaceAll('&#47;', '/');

String archiveHtml(String title, String body) =>
    '''<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self' file:; style-src 'unsafe-inline'">
<title>${htmlEscape(title)}</title><style>
body{max-width:760px;margin:40px auto;padding:0 20px;font-family:system-ui,sans-serif;line-height:1.8;overflow-wrap:anywhere}
img{max-width:100%;height:auto}section{margin:28px 0}small{opacity:.7}blockquote{border-left:3px solid;padding-left:16px;margin-left:0}
p,li,blockquote{white-space:pre-wrap}pre{white-space:pre-wrap}mark{background:#fff1b8;color:inherit}
</style></head><body>$body</body></html>''';

String memoHtml(String? content) {
  final parsed = parseMemoHighlight(content);
  final out = StringBuffer();
  var offset = 0;
  for (final range in parsed.ranges) {
    out.write(htmlEscape(parsed.plainText.substring(offset, range.start)));
    out.write(
      '<mark>${htmlEscape(parsed.plainText.substring(range.start, range.end))}</mark>',
    );
    offset = range.end;
  }
  out.write(htmlEscape(parsed.plainText.substring(offset)));
  return out.toString();
}

/// 앱의 호환 어댑터로 Delta를 얻고 인라인 서식과 줄 단위 서식을 함께 유지한다.
String reflectionHtml(Map<String, dynamic>? content, String? fallback) {
  if (content == null) return '<p>${htmlEscape(fallback)}</p>';
  final ops = const BookReflectionContentAdapter()
      .fromServerJson(content)
      .toDelta()
      .toJson();
  final out = StringBuffer();
  var line = StringBuffer();
  String? list;
  void closeList() {
    if (list != null) out.write('</$list>');
    list = null;
  }

  void flush(Map attrs) {
    final listType = attrs['list'];
    final nextList = listType == 'ordered'
        ? 'ol'
        : listType != null
        ? 'ul'
        : null;
    if (list != nextList) {
      closeList();
      list = nextList;
      if (list != null) out.write('<$list>');
    }
    final header = attrs['header'];
    final tag = list != null
        ? 'li'
        : header is int && header >= 1 && header <= 6
        ? 'h$header'
        : attrs['blockquote'] == true
        ? 'blockquote'
        : attrs['code-block'] == true
        ? 'pre'
        : 'p';
    final styles = <String>[];
    if ({'center', 'right', 'justify'}.contains(attrs['align'])) {
      styles.add('text-align:${attrs['align']}');
    }
    if (attrs['indent'] case final int indent when indent > 0) {
      styles.add('margin-left:${indent.clamp(0, 8) * 20}px');
    }
    final check = listType == 'checked'
        ? '☑ '
        : listType == 'unchecked'
        ? '☐ '
        : '';
    out.write(
      '<$tag style="${styles.join(';')}">$check${line.isEmpty ? '<br>' : line}</$tag>',
    );
    line = StringBuffer();
  }

  for (final op in ops) {
    final insert = op['insert'];
    final attrs = op['attributes'] as Map? ?? const {};
    if (insert is Map && insert['image'] is String) {
      final source = insert['image'] as String;
      // Export 서비스가 확보한 images/ 경로만 사용한다.
      if (source.startsWith('images/')) {
        final width = num.tryParse('${attrs['width']}');
        line.write(
          '<img src="../${htmlEscape(source)}" alt="독후감 이미지"${width != null && width > 0 ? ' width="${width.clamp(1, 2000).round()}"' : ''}>',
        );
      }
    } else if (insert is String) {
      final parts = insert.split('\n');
      for (var i = 0; i < parts.length; i++) {
        var text = htmlEscape(parts[i]);
        for (final style in {
          'bold': 'strong',
          'italic': 'em',
          'underline': 'u',
          'strike': 's',
          'code': 'code',
        }.entries) {
          if (attrs[style.key] == true) {
            text = '<${style.value}>$text</${style.value}>';
          }
        }
        if (attrs['script'] == 'super') text = '<sup>$text</sup>';
        if (attrs['script'] == 'sub') text = '<sub>$text</sub>';
        final colors = <String>[];
        for (final field in {
          'color': 'color',
          'background': 'background-color',
        }.entries) {
          final color = attrs[field.key];
          if (color is String &&
              RegExp(
                r'^(#[0-9a-fA-F]{3,8}|[a-zA-Z]+|rgba?\([0-9., %]+\))$',
              ).hasMatch(color)) {
            colors.add('${field.value}:$color');
          }
        }
        if (colors.isNotEmpty) {
          text = '<span style="${colors.join(';')}">$text</span>';
        }
        final link = attrs['link'];
        if (link is String &&
            {'http', 'https', 'mailto'}.contains(Uri.tryParse(link)?.scheme)) {
          text = '<a href="${htmlEscape(link)}">$text</a>';
        }
        line.write(text);
        if (i < parts.length - 1) flush(attrs);
      }
    }
  }
  if (line.isNotEmpty) flush(const {});
  closeList();
  return out.toString();
}

class ArchiveNames {
  final _used = <String>{};
  String take(String? raw, {String extension = ''}) {
    var name = (raw ?? '')
        .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f\x7f]'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    name = String.fromCharCodes(name.runes.take(60));
    if (name.isEmpty || name == '.' || name == '..') name = '제목 없음';
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      name = '_$name';
    }
    var candidate = '$name$extension';
    var count = 2;
    while (!_used.add(candidate.toLowerCase())) {
      candidate = '$name (${count++})$extension';
    }
    return candidate;
  }
}

String archiveCsv(List<List<Object?>> rows) =>
    '\uFEFF${rows.map((row) => row.map((value) => '"${(value?.toString() ?? '').replaceAll('"', '""')}"').join(',')).join('\r\n')}\r\n';
