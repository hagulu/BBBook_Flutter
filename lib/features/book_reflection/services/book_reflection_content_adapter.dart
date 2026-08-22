import 'package:flutter_quill/flutter_quill.dart';

/// 서버 `contentJson`과 Flutter Quill [Document] 사이의 호환 경계.
///
/// 현재 웹은 Quill Delta(`{ops: [...]}`)를 저장하지만 기존 API 문서와
/// 과거 데이터는 Tiptap/ProseMirror 문서(`{type: doc, content: [...]}`)일 수
/// 있다. 화면은 두 포맷을 구분하지 않고 이 어댑터만 사용한다.
class BookReflectionContentAdapter {
  const BookReflectionContentAdapter();

  Document fromServerJson(Map<String, dynamic>? json) {
    final ops = switch (json) {
      {'ops': final List<dynamic> rawOps} => _normalizeDeltaOps(rawOps),
      {'type': 'doc'} => _tiptapToDelta(json),
      _ => <Map<String, dynamic>>[
        {'insert': '\n'},
      ],
    };
    return Document.fromJson(ops);
  }

  /// 현재 웹 Quill 구현과 호환되는 서버 저장 포맷으로 정규화한다.
  Map<String, dynamic> toServerJson(Document document) {
    return {'ops': document.toDelta().toJson()};
  }

  /// 검색·미리보기용 평문. Quill 문서가 항상 갖는 마지막 개행만 제거한다.
  String toContentText(Document document) {
    final buffer = StringBuffer();
    for (final op in document.toDelta().toJson()) {
      final insert = op['insert'];
      // Quill의 toPlainText()는 이미지 Embed를 U+FFFC 문자로 표현한다.
      // 검색/미리보기 텍스트에는 이미지 자리표시자를 포함하지 않는다.
      if (insert is String) buffer.write(insert);
    }
    return buffer.toString().replaceFirst(RegExp(r'\n+$'), '');
  }

  List<Map<String, dynamic>> _normalizeDeltaOps(List<dynamic> rawOps) {
    final ops = rawOps
        .whereType<Map>()
        .map((op) => Map<String, dynamic>.from(op))
        .toList(growable: true);
    if (ops.isEmpty || !_endsWithNewline(ops.last)) {
      ops.add({'insert': '\n'});
    }
    return ops;
  }

  bool _endsWithNewline(Map<String, dynamic> op) {
    final insert = op['insert'];
    return insert is String && insert.endsWith('\n');
  }

  List<Map<String, dynamic>> _tiptapToDelta(Map<String, dynamic> document) {
    final ops = <Map<String, dynamic>>[];
    final content = document['content'];
    if (content is List) {
      for (final node in content.whereType<Map>()) {
        _appendBlock(ops, Map<String, dynamic>.from(node));
      }
    }
    if (ops.isEmpty || !_endsWithNewline(ops.last)) {
      ops.add({'insert': '\n'});
    }
    return ops;
  }

  void _appendBlock(
    List<Map<String, dynamic>> ops,
    Map<String, dynamic> node, {
    String? listType,
  }) {
    final type = node['type'];
    switch (type) {
      case 'paragraph':
        _appendInlineContent(ops, node['content']);
        _appendLine(ops, listType == null ? null : {'list': listType});
      case 'heading':
        _appendInlineContent(ops, node['content']);
        final attrs = _map(node['attrs']);
        final level = attrs?['level'];
        _appendLine(ops, {'header': level == 2 ? 2 : 1});
      case 'blockquote':
        final children = node['content'];
        if (children is List) {
          for (final child in children.whereType<Map>()) {
            _appendInlineContent(ops, child['content']);
            _appendLine(ops, {'blockquote': true});
          }
        }
      case 'bulletList':
      case 'orderedList':
        final children = node['content'];
        final mappedType = type == 'orderedList' ? 'ordered' : 'bullet';
        if (children is List) {
          for (final child in children.whereType<Map>()) {
            _appendBlock(
              ops,
              Map<String, dynamic>.from(child),
              listType: mappedType,
            );
          }
        }
      case 'listItem':
        final children = node['content'];
        if (children is List) {
          for (final child in children.whereType<Map>()) {
            _appendBlock(
              ops,
              Map<String, dynamic>.from(child),
              listType: listType,
            );
          }
        }
      case 'image':
        _appendImage(ops, node);
        _appendLine(ops, null);
      default:
        final children = node['content'];
        if (children is List) {
          for (final child in children.whereType<Map>()) {
            _appendBlock(ops, Map<String, dynamic>.from(child));
          }
        }
    }
  }

  void _appendInlineContent(List<Map<String, dynamic>> ops, Object? content) {
    if (content is! List) return;
    for (final rawNode in content.whereType<Map>()) {
      final node = Map<String, dynamic>.from(rawNode);
      switch (node['type']) {
        case 'text':
          final text = node['text'];
          if (text is! String || text.isEmpty) continue;
          final attributes = _inlineAttributes(node['marks']);
          ops.add({
            'insert': text,
            if (attributes.isNotEmpty) 'attributes': attributes,
          });
        case 'hardBreak':
          ops.add({'insert': '\n'});
        case 'image':
          _appendImage(ops, node);
      }
    }
  }

  void _appendImage(List<Map<String, dynamic>> ops, Map<String, dynamic> node) {
    final attrs = _map(node['attrs']);
    final src = attrs?['src'];
    if (src is! String || src.isEmpty) return;
    final width = attrs?['width'];
    ops.add({
      'insert': {'image': src},
      if (width != null) 'attributes': {'width': width.toString()},
    });
  }

  Map<String, dynamic> _inlineAttributes(Object? rawMarks) {
    final attributes = <String, dynamic>{};
    if (rawMarks is! List) return attributes;
    for (final rawMark in rawMarks.whereType<Map>()) {
      final mark = Map<String, dynamic>.from(rawMark);
      final attrs = _map(mark['attrs']);
      switch (mark['type']) {
        case 'bold':
          attributes['bold'] = true;
        case 'italic':
          attributes['italic'] = true;
        case 'textStyle':
          final color = attrs?['color'];
          if (color is String && color.isNotEmpty) attributes['color'] = color;
        case 'highlight':
          final color = attrs?['color'];
          if (color is String && color.isNotEmpty) {
            attributes['background'] = color;
          }
      }
    }
    return attributes;
  }

  void _appendLine(
    List<Map<String, dynamic>> ops,
    Map<String, dynamic>? attributes,
  ) {
    ops.add({
      'insert': '\n',
      if (attributes != null && attributes.isNotEmpty) 'attributes': attributes,
    });
  }

  Map<String, dynamic>? _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }
}
