import 'dart:convert';

import '../../book_reflection/services/book_reflection_content_adapter.dart';

/// 버전 1의 휴대 가능한 기록 DTO. DB/서버 PK와 동기화 상태는 포함하지 않는다.
/// id는 관계 및 기존 clientRequestId 중복 판별에 사용하는 UUID다.
class ArchiveRecord {
  ArchiveRecord({required this.id, required Map<String, dynamic> values})
    : values = Map<String, dynamic>.from(values);
  final String id;
  final Map<String, dynamic> values;
  dynamic operator [](String key) => values[key];
  Map<String, dynamic> toJson() => {'id': id, ...values};
}

class RecordArchive {
  RecordArchive({
    required this.exportedAt,
    required this.books,
    required this.notes,
    required this.memos,
    required this.reflections,
    required this.tags,
  });
  final String exportedAt;
  final List<ArchiveRecord> books;
  final List<ArchiveRecord> notes;
  final List<ArchiveRecord> memos;
  final List<ArchiveRecord> reflections;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
    'backupVersion': 1,
    'exportedAt': exportedAt,
    'books': books.map((e) => e.toJson()).toList(),
    'notes': notes.map((e) => e.toJson()).toList(),
    'memos': memos.map((e) => e.toJson()).toList(),
    'reflections': reflections.map((e) => e.toJson()).toList(),
    'tags': tags,
  };

  /// 버전 선택과 각 버전의 파서를 분리해 향후 마이그레이션 진입점을 유지한다.
  static RecordArchive parse(String source) {
    final raw = jsonDecode(source);
    if (raw is! Map<String, dynamic>) {
      throw const ArchiveException('내보내기 파일의 기록 정보가 올바르지 않습니다.');
    }
    switch (raw['backupVersion']) {
      case 1:
        return ArchiveV1Parser().parse(raw);
      case final int version when version > 1:
        throw const ArchiveException(
          '지원하지 않는 백업 버전입니다. 앱을 업데이트한 뒤 다시 시도해 주세요.',
        );
      default:
        throw const ArchiveException('지원하지 않는 백업 버전입니다.');
    }
  }
}

class ArchiveException implements Exception {
  const ArchiveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// DB 컬럼과 별개로 고정된 공개 아카이브 필드 규격.
const archiveBookFields = <String, String>{
  'title': 'string!',
  'author': 'string',
  'publisher': 'string',
  'isbn13': 'string',
  'category': 'string',
  'categoryCode': 'string',
  'statsTotalPages': 'int',
  'displayTotalPages': 'int',
  'status': 'string!',
  'currentPage': 'int!',
  'myRating': 'number',
  'shortReview': 'string',
  'isMasterpiece': 'bool!',
  'wantToReread': 'bool!',
  'rereadCount': 'int!',
  'difficulty': 'string',
  'sourceType': 'string',
  'platformName': 'string',
  'discoverySource': 'string',
  'startedAt': 'date',
  'finishedAt': 'date',
  'libraryDueAt': 'date',
  'createdAt': 'date!',
  'updatedAt': 'date!',
  'coverImage': 'image',
  'tags': 'strings!',
};
const archiveNoteFields = <String, String>{
  'bookId': 'string!',
  'title': 'string',
  'createdAt': 'date!',
  'updatedAt': 'date!',
};
const archiveMemoFields = <String, String>{
  'noteId': 'string!',
  'type': 'string!',
  'startPage': 'int',
  'endPage': 'int',
  'content': 'string',
  'image': 'image',
  'isImportant': 'bool!',
  'sortOrder': 'int!',
  'createdAt': 'date!',
  'updatedAt': 'date!',
};
const archiveReflectionFields = <String, String>{
  'bookId': 'string!',
  'type': 'string!',
  'title': 'string',
  'content': 'document',
  'contentText': 'string',
  'isPublic': 'bool!',
  'isHidden': 'bool!',
  'createdAt': 'date!',
  'updatedAt': 'date!',
};

bool isArchiveImagePath(String value) =>
    RegExp(r'^images/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp)$').hasMatch(value);

class ArchiveV1Parser {
  RecordArchive parse(Map<String, dynamic> json) {
    try {
      final books = _records(json['books'], archiveBookFields);
      final notes = _records(json['notes'], archiveNoteFields);
      final memos = _records(json['memos'], archiveMemoFields);
      final reflections = _records(
        json['reflections'],
        archiveReflectionFields,
      );
      final tags = (json['tags'] as List).cast<String>();
      if (tags.toSet().length != tags.length ||
          tags.any(
            (tag) => tag.trim().isEmpty || tag != tag.trim() || tag.length > 15,
          )) {
        throw const FormatException();
      }
      final date = json['exportedAt'] as String;
      DateTime.parse(date);
      final bookIds = books.map((b) => b.id).toSet();
      final noteIds = notes.map((n) => n.id).toSet();
      for (final record in [...notes, ...reflections]) {
        if (!bookIds.contains(record['bookId'])) throw const FormatException();
      }
      for (final memo in memos) {
        if (!noteIds.contains(memo['noteId']) ||
            !{'SUMMARY', 'QUOTE', 'THOUGHT', 'PHOTO'}.contains(memo['type'])) {
          throw const FormatException();
        }
      }
      for (final book in books) {
        if (!{
          'WANT_TO_READ',
          'READING',
          'FINISHED',
          'PAUSED',
          'STOPPED',
        }.contains(book['status'])) {
          throw const FormatException();
        }
        if ((book['tags'] as List).length > 10 ||
            !(book['tags'] as List).every(tags.contains)) {
          throw const FormatException();
        }
      }
      return RecordArchive(
        exportedAt: date,
        books: books,
        notes: notes,
        memos: memos,
        reflections: reflections,
        tags: tags,
      );
    } on ArchiveException {
      rethrow;
    } catch (_) {
      throw const ArchiveException('내보내기 파일의 기록 정보가 손상되었거나 올바르지 않습니다.');
    }
  }

  List<ArchiveRecord> _records(dynamic raw, Map<String, String> fields) {
    final ids = <String>{};
    return (raw as List).map((entry) {
      final json = Map<String, dynamic>.from(entry as Map);
      final id = json['id'] as String;
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id) || !ids.add(id)) {
        throw const FormatException();
      }
      final values = <String, dynamic>{};
      for (final field in fields.entries) {
        final value = json[field.key];
        final required = field.value.endsWith('!');
        final type = field.value.replaceAll('!', '');
        if (value == null) {
          if (required) throw const FormatException();
        } else {
          final valid = switch (type) {
            'string' => value is String,
            'int' => value is int,
            'number' => value is num && value.isFinite,
            'bool' => value is bool,
            'date' => value is String && DateTime.tryParse(value) != null,
            'image' => value is String && isArchiveImagePath(value),
            'strings' => value is List && value.every((e) => e is String),
            'document' =>
              value is Map<String, dynamic> && _validDocument(value),
            _ => false,
          };
          if (!valid) throw const FormatException();
        }
        values[field.key] = value;
      }
      return ArchiveRecord(id: id, values: values);
    }).toList();
  }

  bool _validDocument(Map<String, dynamic> value) {
    if (value['ops'] is! List && value['type'] != 'doc') return false;
    const adapter = BookReflectionContentAdapter();
    if (!adapter.imageSources(value).every(isArchiveImagePath)) return false;
    adapter.fromServerJson(value);
    return true;
  }
}
