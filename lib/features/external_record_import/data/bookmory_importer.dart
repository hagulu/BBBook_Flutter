import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../bookshelf/models/book_status.dart';
import '../models/external_import_models.dart';

class BookmoryImporter {
  const BookmoryImporter();

  static const maxArchiveBytes = 256 * 1024 * 1024;
  static const maxUncompressedBytes = 1024 * 1024 * 1024;
  static const maxDatabaseBytes = 256 * 1024 * 1024;
  static const maxEntryCount = 4096;

  Future<ExternalImportParseResult> parseFile(File source) async {
    final length = await source.length();
    if (length <= 0 || length > maxArchiveBytes) {
      throw const ExternalImportException(
        '북모리 파일 크기가 너무 크거나 비어 있어요.',
        reason: 'bookmory_archive_size',
      );
    }
    return parseBytes(await source.readAsBytes());
  }

  Future<ExternalImportParseResult> parseBytes(Uint8List bytes) async {
    if (!_hasZipSignature(bytes)) {
      throw const ExternalImportException(
        '올바른 북모리 파일이 아니에요.',
        reason: 'bookmory_signature_invalid',
      );
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      throw const ExternalImportException(
        '북모리 파일이 손상되어 열 수 없어요.',
        reason: 'bookmory_zip_invalid',
      );
    }
    if (archive.length > maxEntryCount) {
      throw const ExternalImportException(
        '북모리 파일에 항목이 너무 많아 안전하게 열 수 없어요.',
        reason: 'bookmory_too_many_entries',
      );
    }

    var uncompressedBytes = 0;
    final databaseEntries = <ArchiveFile>[];
    for (final entry in archive) {
      if (!_isSafeArchivePath(entry.name) || entry.isSymbolicLink) {
        throw const ExternalImportException(
          '안전하지 않은 경로가 포함된 파일이에요.',
          reason: 'bookmory_unsafe_path',
        );
      }
      if (!entry.isFile) continue;
      uncompressedBytes += entry.size;
      if (uncompressedBytes > maxUncompressedBytes) {
        throw const ExternalImportException(
          '압축을 푼 북모리 파일의 크기가 너무 커요.',
          reason: 'bookmory_uncompressed_size',
        );
      }
      final normalized = entry.name.replaceAll('\\', '/');
      if (normalized.split('/').last == 'new_bookmory.db') {
        databaseEntries.add(entry);
      }
    }
    if (databaseEntries.length != 1) {
      throw const ExternalImportException(
        '지원하는 북모리 데이터베이스를 찾지 못했어요.',
        reason: 'bookmory_database_missing',
      );
    }
    final databaseEntry = databaseEntries.single;
    if (databaseEntry.size <= 0 || databaseEntry.size > maxDatabaseBytes) {
      throw const ExternalImportException(
        '북모리 데이터베이스 크기가 너무 커요.',
        reason: 'bookmory_database_size',
      );
    }

    final directory = await Directory.systemTemp.createTemp('bbbook_bookmory_');
    final databasePath = path.join(directory.path, 'new_bookmory.db');
    try {
      final databaseBytes = databaseEntry.readBytes();
      if (databaseBytes == null || databaseBytes.isEmpty) {
        throw const ExternalImportException(
          '북모리 데이터베이스를 읽지 못했어요.',
          reason: 'bookmory_database_decode_failed',
        );
      }
      await File(databasePath).writeAsBytes(databaseBytes, flush: true);
      return await _readDatabase(databasePath);
    } on ExternalImportException {
      rethrow;
    } catch (_) {
      throw const ExternalImportException(
        '북모리 기록을 읽지 못했어요. 지원하지 않는 버전일 수 있어요.',
        reason: 'bookmory_database_invalid',
      );
    } finally {
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
      } catch (_) {
        // 운영체제가 이미 임시 파일을 정리했거나 잠시 잠근 경우다. 원본
        // 공유 URI나 사용자 파일은 건드리지 않고 앱 전용 임시 경로만 쓴다.
      }
    }
  }

  Future<ExternalImportParseResult> _readDatabase(String databasePath) async {
    final database = await openDatabase(
      databasePath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      final tables = await database.query(
        'sqlite_master',
        columns: ['name'],
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'entry'],
        limit: 1,
      );
      if (tables.isEmpty) {
        throw const ExternalImportException(
          '지원하지 않는 북모리 파일 버전이에요.',
          reason: 'bookmory_entry_table_missing',
        );
      }
      final columns = await database.rawQuery('PRAGMA table_info(entry)');
      final names = columns
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();
      if (!names.containsAll({'store', 'key', 'value'})) {
        throw const ExternalImportException(
          '지원하지 않는 북모리 파일 버전이에요.',
          reason: 'bookmory_entry_schema_changed',
        );
      }
      final hasDeleted = names.contains('deleted');
      final rows = await database.query(
        'entry',
        columns: ['store', 'key', 'value'],
        where: hasDeleted
            ? "store IN (?, ?) AND (deleted IS NULL OR deleted = 0)"
            : 'store IN (?, ?)',
        whereArgs: ['books', 'notes'],
      );
      return _parseEntryRows(rows);
    } finally {
      await database.close();
    }
  }

  ExternalImportParseResult _parseEntryRows(List<Map<String, Object?>> rows) {
    final bookRows = rows.where((row) => row['store'] == 'books').toList();
    final noteRows = rows.where((row) => row['store'] == 'notes').toList();
    final drafts = <String, _BookmoryBookDraft>{};
    var skipped = 0;
    var warnings = 0;

    for (final row in bookRows) {
      final key = row['key']?.toString();
      final value = row['value'];
      if (key == null || value is! String) {
        skipped++;
        continue;
      }
      try {
        final json = jsonDecode(value);
        if (json is! Map<String, dynamic>) {
          skipped++;
          continue;
        }
        final parsed = _parseBook(key, json);
        if (parsed == null) {
          skipped++;
          continue;
        }
        warnings += parsed.warnings;
        drafts[key] = parsed;
      } catch (_) {
        skipped++;
      }
    }

    for (final row in noteRows) {
      final value = row['value'];
      if (value is! String) {
        skipped++;
        continue;
      }
      try {
        final json = jsonDecode(value);
        if (json is! Map<String, dynamic>) {
          skipped++;
          continue;
        }
        final bid = _string(json['bid']);
        final target = bid == null ? null : drafts[bid];
        final note = _parseNote(row['key']?.toString(), json);
        if (target == null || note == null) {
          skipped++;
          continue;
        }
        target.notes.add(note);
      } catch (_) {
        skipped++;
      }
    }

    return ExternalImportParseResult(
      source: ExternalImportSource.bookmory,
      books: drafts.values
          .map((draft) => draft.toItem())
          .toList(growable: false),
      discoveredBookCount: bookRows.length,
      skippedItemCount: skipped,
      warningCount: warnings,
    );
  }

  _BookmoryBookDraft? _parseBook(String key, Map<String, dynamic> json) {
    final title = _string(json['title'])?.trim();
    if (title == null || title.isEmpty || title.length > 255) return null;

    final reads = _mapList(json['reads']);
    reads.sort((a, b) {
      final nth = _integer(a['nth']).compareTo(_integer(b['nth']));
      if (nth != 0) return nth;
      return _integer(a['created_at']).compareTo(_integer(b['created_at']));
    });
    final latestRead = reads.isEmpty ? null : reads.last;
    final completedReads = reads
        .where((read) => _string(read['status']) == 'DONE')
        .toList(growable: false);
    final latestCompleted = completedReads.isEmpty ? null : completedReads.last;

    final rawStatus =
        _string(latestRead?['status']) ??
        _stringList(json['status_list']).lastOrNull ??
        (json['wishlist'] == true ? 'NOT_STARTED' : null);
    final mappedStatus = _status(rawStatus);
    var warnings = mappedStatus.recognized ? 0 : 1;

    final sourceType = _sourceType(
      _string(latestRead?['book_type']) ?? _string(json['book_type']),
    );
    if (sourceType == null &&
        (_string(latestRead?['book_type']) ?? _string(json['book_type'])) !=
            null) {
      warnings++;
    }
    final pageType =
        _string(latestRead?['page_type']) ?? _string(json['page_type']);
    var totalPages =
        _positiveInt(latestRead?['real_total_page']) ??
        _positiveInt(latestRead?['total_page']) ??
        _positiveInt(json['real_total_page']) ??
        _positiveInt(json['total_page']);
    var currentPage = mappedStatus.status == BookStatus.wantToRead
        ? 0
        : (_nonNegativeInt(latestRead?['page']) ??
              _nonNegativeInt(json['cur_page']) ??
              0);
    if (sourceType == ExternalBookSourceType.audioBook) {
      currentPage = currentPage.clamp(0, 100);
      totalPages = null;
    } else if (sourceType == ExternalBookSourceType.ebook &&
        pageType == 'PERCENT') {
      currentPage = currentPage.clamp(0, 100);
      totalPages = 100;
    } else if (totalPages != null) {
      currentPage = currentPage.clamp(0, totalPages);
    }

    final authorNames = _stringList(json['authors']);
    if (authorNames.isEmpty) {
      final singular = _string(json['author']);
      if (singular != null && singular.trim().isNotEmpty) {
        authorNames.add(singular.trim());
      }
    }
    authorNames.addAll(_stringList(json['translators']));
    final author = authorNames.isEmpty ? null : authorNames.toSet().join(', ');

    final rating = _rating(latestCompleted?['star']);
    final rawRating = _number(latestCompleted?['star']);
    if (rawRating != null && rawRating != 0 && rating == null) warnings++;

    final currentOffset = _integerOrNull(
      latestRead?['start_recorded_tz_offset'],
    );
    final completedOffset = _integerOrNull(
      latestCompleted?['end_recorded_tz_offset'],
    );
    return _BookmoryBookDraft(
      sourceBookId: key,
      isbn13: _isbn13(json['isbn']),
      title: title,
      author: _limit(author, 255),
      publisher: _limit(_string(json['publisher']), 255),
      status: mappedStatus.status,
      currentPage: currentPage,
      totalPages: totalPages,
      rating: rating,
      shortReview: _limit(_string(latestCompleted?['comment'])?.trim(), 150),
      startedAt: _epochDate(latestRead?['start'], currentOffset),
      finishedAt: _epochDate(latestCompleted?['end'], completedOffset),
      rereadCount: completedReads.length,
      sourceType: sourceType,
      coverImageUrl: _httpUrl(json['image']),
      createdAt: _epochInstant(json['created_at']),
      tags: _tags(json['tags']),
      warnings: warnings,
    );
  }

  ExternalNoteImportItem? _parseNote(String? key, Map<String, dynamic> json) {
    final type = switch (_string(json['type'])) {
      'SUMMARY' => ExternalNoteType.summary,
      'BOOK_CONTENT' => ExternalNoteType.quote,
      'THOUGHT' => ExternalNoteType.thought,
      _ => null,
    };
    if (type == null) return null;
    final rawDelta = _string(json['content_quill']);
    if (rawDelta == null) return null;
    final content = quillDeltaToPlainText(rawDelta);
    if (content.isEmpty) return null;
    final startPage = _positiveInt(json['page']);
    final rawEndPage = _positiveInt(json['page_end']);
    final endPage =
        startPage != null && rawEndPage != null && rawEndPage < startPage
        ? null
        : rawEndPage;
    return ExternalNoteImportItem(
      type: type,
      content: content,
      sourceNoteId: key,
      startPage: startPage,
      endPage: endPage,
      createdAt: _epochInstant(json['created_at']),
    );
  }

  static String quillDeltaToPlainText(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List<dynamic>) return '';
    final lines = <String>[];
    var line = StringBuffer();
    var orderedIndex = 1;
    for (final operation in decoded) {
      if (operation is! Map<String, dynamic>) continue;
      final insert = operation['insert'];
      if (insert is! String) continue;
      final attributes = operation['attributes'];
      final listType = attributes is Map<String, dynamic>
          ? attributes['list']?.toString()
          : null;
      for (final rune in insert.runes) {
        if (rune != 10) {
          line.writeCharCode(rune);
          continue;
        }
        final text = line.toString();
        line = StringBuffer();
        final marker = switch (listType) {
          'bullet' => '- ',
          'ordered' => '${orderedIndex++}. ',
          _ => '',
        };
        lines.add(text.isEmpty ? '' : '$marker$text');
        if (listType != 'ordered') orderedIndex = 1;
      }
    }
    if (line.isNotEmpty) lines.add(line.toString());
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    return lines.join('\n').trim();
  }

  bool _hasZipSignature(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) return false;
    return (bytes[2] == 0x03 && bytes[3] == 0x04) ||
        (bytes[2] == 0x05 && bytes[3] == 0x06) ||
        (bytes[2] == 0x07 && bytes[3] == 0x08);
  }

  bool _isSafeArchivePath(String value) {
    final normalized = value.replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.contains('\u0000') ||
        normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      return false;
    }
    return !normalized.split('/').contains('..');
  }

  ({BookStatus status, bool recognized}) _status(String? value) {
    return switch (value) {
      'DONE' => (status: BookStatus.finished, recognized: true),
      'READING' => (status: BookStatus.reading, recognized: true),
      'NOT_STARTED' => (status: BookStatus.wantToRead, recognized: true),
      'PAUSED' => (status: BookStatus.paused, recognized: true),
      'GIVE_UP' ||
      'GIVEN_UP' ||
      'STOPPED' => (status: BookStatus.stopped, recognized: true),
      _ => (status: BookStatus.wantToRead, recognized: false),
    };
  }

  ExternalBookSourceType? _sourceType(String? value) => switch (value) {
    'paperBook' ||
    'hardCover' ||
    'pocketBook' => ExternalBookSourceType.paperBook,
    'eBook' => ExternalBookSourceType.ebook,
    'audioBook' => ExternalBookSourceType.audioBook,
    _ => null,
  };

  List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List<dynamic>) return [];
    return value.whereType<Map<String, dynamic>>().toList();
  }

  List<String> _stringList(Object? value) {
    if (value is! List<dynamic>) return [];
    return value
        .whereType<String>()
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  String? _string(Object? value) => value is String ? value : null;

  num? _number(Object? value) {
    if (value is num) return value;
    return value is String ? num.tryParse(value) : null;
  }

  int _integer(Object? value) => _number(value)?.round() ?? 0;
  int? _integerOrNull(Object? value) => _number(value)?.round();

  int? _positiveInt(Object? value) {
    final parsed = _integerOrNull(value);
    return parsed == null || parsed <= 0 ? null : parsed;
  }

  int? _nonNegativeInt(Object? value) {
    final parsed = _integerOrNull(value);
    return parsed == null || parsed < 0 ? null : parsed;
  }

  String? _isbn13(Object? value) {
    final normalized = _string(value)?.replaceAll(RegExp(r'[^0-9]'), '');
    return normalized != null && RegExp(r'^\d{13}$').hasMatch(normalized)
        ? normalized
        : null;
  }

  double? _rating(Object? value) {
    final parsed = _number(value)?.toDouble();
    if (parsed == null || parsed <= 0 || parsed > 5) return null;
    return (parsed * 10).round() / 10;
  }

  DateTime? _epochInstant(Object? value) {
    final milliseconds = _integerOrNull(value);
    if (milliseconds == null || milliseconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  DateTime? _epochDate(Object? value, int? offsetSeconds) {
    final milliseconds = _integerOrNull(value);
    if (milliseconds == null || milliseconds <= 0) return null;
    final shifted =
        DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true).add(
          Duration(
            seconds: offsetSeconds ?? DateTime.now().timeZoneOffset.inSeconds,
          ),
        );
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  String? _httpUrl(Object? value) {
    final raw = _string(value)?.trim();
    if (raw == null || raw.length > 500) return null;
    final uri = Uri.tryParse(raw);
    return uri != null &&
            uri.hasAuthority &&
            (uri.scheme == 'http' || uri.scheme == 'https')
        ? raw
        : null;
  }

  String? _limit(String? value, int maxLength) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.length <= maxLength) return normalized;
    final result = StringBuffer();
    for (final rune in normalized.runes) {
      final character = String.fromCharCode(rune);
      if (result.length + character.length > maxLength) break;
      result.write(character);
    }
    return result.toString();
  }

  List<String> _tags(Object? value) {
    final raw = <String>[];
    if (value is List<dynamic>) {
      raw.addAll(value.whereType<String>());
    } else if (value is String) {
      raw.addAll(value.split(RegExp(r'\s+(?=#)')));
    }
    final result = <String>[];
    for (final entry in raw) {
      final normalized = entry.trim().replaceFirst(RegExp(r'^#'), '');
      if (normalized.isEmpty || normalized.length > 15) continue;
      if (!result.contains(normalized)) result.add(normalized);
      if (result.length == 10) break;
    }
    return result;
  }
}

class _BookmoryBookDraft {
  _BookmoryBookDraft({
    required this.sourceBookId,
    required this.isbn13,
    required this.title,
    required this.author,
    required this.publisher,
    required this.status,
    required this.currentPage,
    required this.totalPages,
    required this.rating,
    required this.shortReview,
    required this.startedAt,
    required this.finishedAt,
    required this.rereadCount,
    required this.sourceType,
    required this.coverImageUrl,
    required this.createdAt,
    required this.tags,
    required this.warnings,
  });

  final String sourceBookId;
  final String? isbn13;
  final String title;
  final String? author;
  final String? publisher;
  final BookStatus status;
  final int currentPage;
  final int? totalPages;
  final double? rating;
  final String? shortReview;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int rereadCount;
  final ExternalBookSourceType? sourceType;
  final String? coverImageUrl;
  final DateTime? createdAt;
  final List<String> tags;
  final int warnings;
  final List<ExternalNoteImportItem> notes = [];

  ExternalBookImportItem toItem() => ExternalBookImportItem(
    source: ExternalImportSource.bookmory,
    sourceBookId: sourceBookId,
    isbn13: isbn13,
    title: title,
    author: author,
    publisher: publisher,
    status: status,
    currentPage: currentPage,
    totalPages: totalPages,
    rating: rating,
    shortReview: shortReview,
    startedAt: startedAt,
    finishedAt: finishedAt,
    rereadCount: rereadCount,
    sourceType: sourceType,
    coverImageUrl: coverImageUrl,
    createdAt: createdAt,
    notes: List.unmodifiable(notes),
    tags: List.unmodifiable(tags),
  );
}
