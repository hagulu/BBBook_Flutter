import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../../bookshelf/models/book_status.dart';
import '../models/external_import_models.dart';

class BookJukImporter {
  const BookJukImporter();

  static const requiredHeaders = {'제목', '저자', '출판사', '독서상태'};
  static final _memoHeaderPattern = RegExp(r'^메모(\d+)$');
  static final _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  ExternalImportParseResult parseBytes(Uint8List bytes) {
    final String contents;
    try {
      contents = utf8.decode(bytes);
    } on FormatException {
      throw const ExternalImportException(
        'UTF-8 형식의 북적북적 CSV 파일만 가져올 수 있어요.',
        reason: 'csv_not_utf8',
      );
    }

    final List<List<dynamic>> rows;
    try {
      rows = csv.decode(contents);
    } catch (_) {
      throw const ExternalImportException(
        'CSV 파일을 읽지 못했어요. 북적북적에서 다시 내보내 주세요.',
        reason: 'csv_decode_failed',
      );
    }
    if (rows.isEmpty) {
      throw const ExternalImportException(
        '비어 있는 CSV 파일이에요.',
        reason: 'csv_empty',
      );
    }

    final headers = <String, int>{};
    for (var index = 0; index < rows.first.length; index++) {
      final header = rows.first[index]
          .toString()
          .replaceFirst('\ufeff', '')
          .trim();
      if (header.isNotEmpty) headers.putIfAbsent(header, () => index);
    }
    if (!requiredHeaders.every(headers.containsKey)) {
      throw const ExternalImportException(
        '북적북적에서 내보낸 CSV 파일이 아니에요.',
        reason: 'csv_headers_not_supported',
      );
    }

    final memoColumns = <({int number, int index})>[];
    for (final entry in headers.entries) {
      final match = _memoHeaderPattern.firstMatch(entry.key);
      if (match == null) continue;
      memoColumns.add((number: int.parse(match.group(1)!), index: entry.value));
    }
    memoColumns.sort((a, b) => a.number.compareTo(b.number));

    final books = <ExternalBookImportItem>[];
    var skipped = 0;
    var warnings = 0;
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      String value(String header) {
        final index = headers[header];
        if (index == null || index >= row.length) return '';
        return row[index]?.toString() ?? '';
      }

      final title = value('제목').trim();
      if (title.isEmpty || title.length > 255) {
        skipped++;
        continue;
      }
      final statusResult = _parseStatus(value('독서상태').trim());
      if (!statusResult.recognized) warnings++;

      DateTime? date(String header) {
        final raw = value(header).trim();
        if (raw.isEmpty) return null;
        final parsed = _parseDate(raw);
        if (parsed == null) warnings++;
        return parsed;
      }

      final notes = <ExternalNoteImportItem>[];
      for (final column in memoColumns) {
        if (column.index >= row.length) continue;
        final content = row[column.index]?.toString().trim() ?? '';
        if (content.isEmpty) continue;
        notes.add(
          ExternalNoteImportItem(
            type: ExternalNoteType.summary,
            content: content,
            sourceNoteId: 'memo${column.number}',
          ),
        );
      }

      final sourceBookId = value('인덱스').trim();
      final author = _nullable(value('저자'), maxLength: 255);
      final publisher = _nullable(value('출판사'), maxLength: 255);
      books.add(
        ExternalBookImportItem(
          source: ExternalImportSource.bookJuk,
          sourceBookId: sourceBookId.isEmpty ? 'row_$rowIndex' : sourceBookId,
          title: title,
          author: author,
          publisher: publisher,
          status: statusResult.status,
          currentPage: 0,
          rereadCount: statusResult.status == BookStatus.finished ? 1 : 0,
          startedAt: date('시작일'),
          finishedAt: date('읽은 날짜'),
          createdAt: date('생성일'),
          notes: notes,
          tags: const [],
        ),
      );
    }

    return ExternalImportParseResult(
      source: ExternalImportSource.bookJuk,
      books: books,
      discoveredBookCount: rows.length - 1,
      skippedItemCount: skipped,
      warningCount: warnings,
    );
  }

  ({BookStatus status, bool recognized}) _parseStatus(String value) {
    return switch (value) {
      '읽은 책' => (status: BookStatus.finished, recognized: true),
      '읽고 있는 책' => (status: BookStatus.reading, recognized: true),
      '읽고 싶은 책' => (status: BookStatus.wantToRead, recognized: true),
      '잠시 멈춘 책' => (status: BookStatus.paused, recognized: true),
      '중단한 책' || '읽기를 중단한 책' => (status: BookStatus.stopped, recognized: true),
      _ => (status: BookStatus.wantToRead, recognized: false),
    };
  }

  DateTime? _parseDate(String value) {
    final match = _datePattern.firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day
        ? parsed
        : null;
  }

  String? _nullable(String value, {int? maxLength}) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    if (maxLength == null || normalized.length <= maxLength) return normalized;
    final result = StringBuffer();
    for (final rune in normalized.runes) {
      final character = String.fromCharCode(rune);
      if (result.length + character.length > maxLength) break;
      result.write(character);
    }
    return result.toString();
  }
}
