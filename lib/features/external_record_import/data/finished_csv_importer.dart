import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';

import '../../bookshelf/models/book_status.dart';
import '../models/external_import_models.dart';

/// "완독 기록 가져오기" CSV(`docs/porting-reference/my-import.md`,
/// `api-me-books-import-finished-csv-post.md`) 파서.
///
/// 서버 CSV Import와 같은 규칙으로 행마다 검증해, 조건을 어긴 행만
/// [ExternalImportParseResult.rowFailures]로 모으고 나머지 행은 완독 상태의
/// 책으로 넘긴다. 기존 책과 같은 ISBN이면 건너뛰는 처리는 분석 이후
/// [ExternalImportController]의 충돌 제외 규칙이 맡는다.
class FinishedCsvImporter {
  const FinishedCsvImporter({this.uuid = const Uuid()});

  final Uuid uuid;

  static const headers = [
    'title',
    'author',
    'publisher',
    'isbn13',
    'total_pages',
    'started_at',
    'finished_at',
    'my_rating',
    'short_review',
    'source_type',
    'platform_name',
    'difficulty',
    'discovery_source',
    'is_masterpiece',
    'reread_count',
    'tags',
  ];

  static const _maxTextLength = 255;
  static const _maxShortReviewLength = 150;
  static const _maxPlatformNameLength = 50;
  static const _maxDiscoverySourceLength = 50;
  static const _maxTagLength = 15;
  static const _maxTagsPerBook = 10;

  static final _isbnSeparatorPattern = RegExp(r'[-\s]');
  static final _isbnPattern = RegExp(r'^\d{13}$');
  static final _pagesPattern = RegExp(r'^\d+$');
  static final _ratingPattern = RegExp(r'^\d+(\.\d)?$');
  static final _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  ExternalImportParseResult parseBytes(Uint8List bytes) {
    final String contents;
    try {
      contents = utf8.decode(bytes);
    } on FormatException {
      throw const ExternalImportException(
        'UTF-8로 저장된 CSV 파일만 가져올 수 있어요.',
        reason: 'csv_not_utf8',
      );
    }

    final List<List<dynamic>> rows;
    try {
      rows = csv.decode(contents);
    } catch (_) {
      throw const ExternalImportException(
        'CSV 파일을 읽지 못했어요. 파일 내용을 확인해 주세요.',
        reason: 'csv_decode_failed',
      );
    }
    if (rows.isEmpty) {
      throw const ExternalImportException(
        '비어 있는 CSV 파일이에요.',
        reason: 'csv_empty',
      );
    }

    final columns = <String, int>{};
    for (var index = 0; index < rows.first.length; index++) {
      final header = rows.first[index]
          .toString()
          .replaceFirst('\ufeff', '')
          .trim();
      if (header.isNotEmpty) columns.putIfAbsent(header, () => index);
    }
    // title 외 컬럼은 모두 선택이다. 헤더에 없는 컬럼은 빈 값으로 본다
    // (기존 10개 컬럼 CSV도 그대로 가져온다).
    if (!columns.containsKey('title')) {
      throw const ExternalImportException(
        'CSV 형식이 올바르지 않아요. 첫 줄의 헤더를 확인해 주세요.',
        reason: 'csv_headers_not_supported',
      );
    }

    final books = <ExternalBookImportItem>[];
    final failures = <ExternalImportRowFailure>[];
    var dataRowCount = 0;
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      String value(String header) {
        final index = columns[header];
        if (index == null || index >= row.length) return '';
        return row[index]?.toString().trim() ?? '';
      }

      // 파일 끝 빈 줄처럼 모든 칸이 빈 행은 데이터 행으로 세지 않는다.
      if (headers.every((header) => value(header).isEmpty)) continue;
      dataRowCount++;

      final title = value('title');
      final parsed = _parseRow(value);
      switch (parsed) {
        case _RowFailure(:final reason):
          failures.add(
            ExternalImportRowFailure(
              row: rowIndex + 1,
              title: title.isEmpty ? null : title,
              reason: reason,
            ),
          );
        case _RowBook(:final book):
          books.add(book);
      }
    }
    if (dataRowCount == 0) {
      throw const ExternalImportException(
        'CSV 파일에 가져올 기록이 없어요.',
        reason: 'csv_no_rows',
      );
    }

    return ExternalImportParseResult(
      source: ExternalImportSource.finishedCsv,
      books: books,
      discoveredBookCount: dataRowCount,
      skippedItemCount: failures.length,
      warningCount: 0,
      rowFailures: failures,
    );
  }

  _RowResult _parseRow(String Function(String header) value) {
    final title = value('title');
    if (title.isEmpty) return const _RowFailure('제목이 비어 있어요.');
    if (title.length > _maxTextLength) {
      return const _RowFailure('제목은 255자까지 입력할 수 있어요.');
    }
    final author = value('author');
    if (author.length > _maxTextLength) {
      return const _RowFailure('저자는 255자까지 입력할 수 있어요.');
    }
    final publisher = value('publisher');
    if (publisher.length > _maxTextLength) {
      return const _RowFailure('출판사는 255자까지 입력할 수 있어요.');
    }

    final isbn13 = value('isbn13').replaceAll(_isbnSeparatorPattern, '');
    if (isbn13.isNotEmpty && !_isbnPattern.hasMatch(isbn13)) {
      return const _RowFailure('ISBN-13은 13자리 숫자로 입력해 주세요.');
    }

    final rawPages = value('total_pages');
    int? totalPages;
    if (rawPages.isNotEmpty) {
      totalPages = _pagesPattern.hasMatch(rawPages)
          ? int.tryParse(rawPages)
          : null;
      if (totalPages == null || totalPages <= 0) {
        return const _RowFailure('총 페이지 수는 1 이상의 숫자로 입력해 주세요.');
      }
    }

    final rawStartedAt = value('started_at');
    DateTime? startedAt;
    if (rawStartedAt.isNotEmpty) {
      startedAt = _parseDate(rawStartedAt);
      if (startedAt == null) {
        return const _RowFailure('시작일은 yyyy-MM-dd 형식으로 입력해 주세요.');
      }
    }

    final rawFinishedAt = value('finished_at');
    final DateTime finishedAt;
    if (rawFinishedAt.isNotEmpty) {
      final parsed = _parseDate(rawFinishedAt);
      if (parsed == null) {
        return const _RowFailure('완독일은 yyyy-MM-dd 형식으로 입력해 주세요.');
      }
      finishedAt = parsed;
    } else {
      finishedAt = _todayInKst();
    }
    // 완독일을 비워 오늘로 채운 경우도 같은 기준으로 비교한다.
    if (startedAt != null && startedAt.isAfter(finishedAt)) {
      return const _RowFailure('시작일이 완독일보다 늦어요.');
    }

    final rawRating = value('my_rating');
    double? rating;
    if (rawRating.isNotEmpty) {
      rating = _ratingPattern.hasMatch(rawRating)
          ? double.tryParse(rawRating)
          : null;
      if (rating == null || rating < 0.5 || rating > 5.0) {
        return const _RowFailure('별점은 0.5 ~ 5.0 사이로, 소수점 첫째 자리까지 입력해 주세요.');
      }
    }

    final shortReview = value('short_review');
    if (shortReview.length > _maxShortReviewLength) {
      return const _RowFailure('한줄 감상은 150자까지 입력할 수 있어요.');
    }

    final rawSourceType = value('source_type');
    ExternalBookSourceType? sourceType;
    if (rawSourceType.isNotEmpty) {
      sourceType = _parseSourceType(rawSourceType);
      if (sourceType == null) {
        return const _RowFailure(
          '독서 매체는 PAPER_BOOK, EBOOK, AUDIO_BOOK 중 하나로 입력해 주세요.',
        );
      }
    }

    final platformName = value('platform_name');
    if (platformName.length > _maxPlatformNameLength) {
      return const _RowFailure('플랫폼명은 50자까지 입력할 수 있어요.');
    }

    final rawDifficulty = value('difficulty');
    final difficulty = _parseDifficulty(rawDifficulty);
    // 앱·웹은 세 저장값만 난이도로 표시하므로, 그 밖의 값은 저장해도 보이지
    // 않는다. 독서 매체처럼 허용 값이 아니면 그 행을 실패로 알린다.
    if (rawDifficulty.isNotEmpty && difficulty == null) {
      return const _RowFailure('난이도는 EASY, MODERATE, HARD 중 하나로 입력해 주세요.');
    }

    final discoverySource = value('discovery_source');
    if (discoverySource.length > _maxDiscoverySourceLength) {
      return const _RowFailure('알게 된 경로는 50자까지 입력할 수 있어요.');
    }

    final rawMasterpiece = value('is_masterpiece').toLowerCase();
    final bool isMasterpiece;
    switch (rawMasterpiece) {
      case '' || 'false':
        isMasterpiece = false;
      case 'true':
        isMasterpiece = true;
      default:
        return const _RowFailure('명작 여부는 true 또는 false로 입력해 주세요.');
    }

    final rawRereadCount = value('reread_count');
    var rereadCount = 1;
    if (rawRereadCount.isNotEmpty) {
      final parsed = _pagesPattern.hasMatch(rawRereadCount)
          ? int.tryParse(rawRereadCount)
          : null;
      if (parsed == null || parsed <= 0) {
        return const _RowFailure('회독 수는 1 이상의 숫자로 입력해 주세요.');
      }
      rereadCount = parsed;
    }

    final tags = <String>{
      for (final tag in value('tags').split('|'))
        if (tag.trim().isNotEmpty) tag.trim(),
    }.toList(growable: false);
    if (tags.any((tag) => tag.length > _maxTagLength)) {
      return const _RowFailure('태그는 하나에 15자까지 입력할 수 있어요.');
    }
    if (tags.length > _maxTagsPerBook) {
      return const _RowFailure('태그는 책 한 권에 10개까지 입력할 수 있어요.');
    }

    final isAudioBook = sourceType == ExternalBookSourceType.audioBook;
    return _RowBook(
      ExternalBookImportItem(
        source: ExternalImportSource.finishedCsv,
        // ISBN 없는 행은 서버처럼 중복 검사 없이 모두 등록한다. 같은 제목의
        // 행이나 다음에 다시 가져온 행이 같은 식별자로 합쳐지지 않도록 행마다
        // 새 식별자를 준다.
        sourceBookId: uuid.v4(),
        title: title,
        author: author.isEmpty ? null : author,
        publisher: publisher.isEmpty ? null : publisher,
        isbn13: isbn13.isEmpty ? null : isbn13,
        status: BookStatus.finished,
        // 완독 책은 진행 위치를 끝으로 맞춘다(오디오북은 퍼센트 기준).
        currentPage: isAudioBook ? 100 : totalPages ?? 0,
        totalPages: totalPages,
        rating: rating,
        shortReview: shortReview.isEmpty ? null : shortReview,
        startedAt: startedAt,
        finishedAt: finishedAt,
        rereadCount: rereadCount,
        sourceType: sourceType,
        // 종이책은 플랫폼을 쓰지 않으므로 값이 있어도 무시한다.
        platformName:
            platformName.isEmpty ||
                sourceType == ExternalBookSourceType.paperBook
            ? null
            : platformName,
        difficulty: difficulty,
        discoverySource: discoverySource.isEmpty ? null : discoverySource,
        isMasterpiece: isMasterpiece,
        notes: const [],
        tags: tags,
      ),
    );
  }

  /// 웹 AI 프롬프트가 안내하던 `AUDIOBOOK` 표기로 만든 파일도 오디오북으로
  /// 받아준다. 저장 값은 API 규격(`AUDIO_BOOK`)을 따른다.
  ExternalBookSourceType? _parseSourceType(String value) {
    return switch (value.toUpperCase()) {
      'PAPER_BOOK' => ExternalBookSourceType.paperBook,
      'EBOOK' => ExternalBookSourceType.ebook,
      'AUDIO_BOOK' || 'AUDIOBOOK' => ExternalBookSourceType.audioBook,
      _ => null,
    };
  }

  /// 앱과 웹은 난이도를 `EASY`/`MODERATE`/`HARD`로 저장하고 표시할 때만
  /// 한글로 바꾼다(`DifficultyLevel`). 대소문자나 한글 표기로 적은 값도 이
  /// 저장값으로 맞춘다.
  String? _parseDifficulty(String value) {
    return switch (value.toUpperCase()) {
      'EASY' || '쉬움' => 'EASY',
      'MODERATE' || '보통' => 'MODERATE',
      'HARD' || '어려움' => 'HARD',
      _ => null,
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

  /// 서버가 `X-Timezone: Asia/Seoul` 기준 오늘로 채우는 것과 같게, 기기
  /// 타임존과 무관하게 KST(UTC+9) 기준 오늘 날짜를 쓴다.
  DateTime _todayInKst() {
    final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    return DateTime(kstNow.year, kstNow.month, kstNow.day);
  }
}

sealed class _RowResult {
  const _RowResult();
}

class _RowFailure extends _RowResult {
  const _RowFailure(this.reason);

  final String reason;
}

class _RowBook extends _RowResult {
  const _RowBook(this.book);

  final ExternalBookImportItem book;
}
