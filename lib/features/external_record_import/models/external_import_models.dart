import '../../bookshelf/models/book_status.dart';

enum ExternalImportSource {
  bookJuk('BOOK_JUK', '북적북적'),
  bookmory('BOOKMORY', '북모리'),

  /// 책 추가 화면의 "완독 기록 가져오기"(`my-import.md`) 전용 CSV. 다른
  /// 서비스 기록 가져오기 안내 화면에는 노출하지 않는다.
  finishedCsv('FINISHED_CSV', '완독 기록');

  const ExternalImportSource(this.code, this.label);

  final String code;
  final String label;
}

enum ExternalBookSourceType {
  paperBook('PAPER_BOOK'),
  ebook('EBOOK'),
  audioBook('AUDIO_BOOK');

  const ExternalBookSourceType(this.apiValue);

  final String apiValue;
}

enum ExternalNoteType { summary, quote, thought }

class ExternalNoteImportItem {
  const ExternalNoteImportItem({
    required this.type,
    required this.content,
    this.sourceNoteId,
    this.startPage,
    this.endPage,
    this.createdAt,
  });

  final ExternalNoteType type;
  final String content;
  final String? sourceNoteId;
  final int? startPage;
  final int? endPage;
  final DateTime? createdAt;
}

class ExternalBookImportItem {
  const ExternalBookImportItem({
    required this.source,
    required this.title,
    required this.status,
    required this.currentPage,
    required this.rereadCount,
    required this.notes,
    required this.tags,
    this.sourceBookId,
    this.isbn13,
    this.author,
    this.publisher,
    this.totalPages,
    this.rating,
    this.shortReview,
    this.startedAt,
    this.finishedAt,
    this.sourceType,
    this.platformName,
    this.difficulty,
    this.discoverySource,
    this.isMasterpiece,
    this.coverImageUrl,
    this.createdAt,
  });

  final ExternalImportSource source;
  final String? sourceBookId;
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
  final String? platformName;
  final String? difficulty;
  final String? discoverySource;

  /// null이면 기존 책의 값을 유지한다(새 책은 false).
  final bool? isMasterpiece;
  final String? coverImageUrl;
  final DateTime? createdAt;
  final List<ExternalNoteImportItem> notes;
  final List<String> tags;
}

/// 파일 안에서 형식 조건을 어겨 가져오지 않는 행. 완독 CSV처럼 행 단위로
/// 실패를 알려줘야 하는 파서만 채운다.
class ExternalImportRowFailure {
  const ExternalImportRowFailure({
    required this.row,
    required this.title,
    required this.reason,
  });

  /// CSV 파일 행 번호(1은 헤더, 데이터는 2부터).
  final int row;
  final String? title;
  final String reason;
}

class ExternalImportParseResult {
  const ExternalImportParseResult({
    required this.source,
    required this.books,
    required this.discoveredBookCount,
    required this.skippedItemCount,
    required this.warningCount,
    this.rowFailures = const [],
  });

  final ExternalImportSource source;
  final List<ExternalBookImportItem> books;
  final int discoveredBookCount;
  final int skippedItemCount;
  final int warningCount;
  final List<ExternalImportRowFailure> rowFailures;

  int get noteCount => books.fold(0, (sum, book) => sum + book.notes.length);
  int get importableRecordCount => books.length;
}

class ExternalImportException implements Exception {
  const ExternalImportException(this.userMessage, {required this.reason});

  final String userMessage;
  final String reason;

  @override
  String toString() => 'ExternalImportException(reason: $reason)';
}

class ExternalImportFileReference {
  const ExternalImportFileReference({
    required this.path,
    required this.displayName,
    this.deleteWhenDone = false,
    this.platformErrorMessage,
    this.expectedSource,
  });

  final String path;
  final String displayName;
  final bool deleteWhenDone;
  final String? platformErrorMessage;

  /// 지정하면 확장자·헤더로 서비스를 추측하지 않고 이 형식으로만 분석한다.
  final ExternalImportSource? expectedSource;

  factory ExternalImportFileReference.fromPlatformMap(
    Map<Object?, Object?> value,
  ) {
    final path = value['path'];
    final displayName = value['displayName'];
    final errorMessage = value['errorMessage'];
    if (path is! String ||
        displayName is! String ||
        (path.isEmpty && errorMessage is! String)) {
      throw const FormatException('Invalid shared file payload');
    }
    return ExternalImportFileReference(
      path: path,
      displayName: displayName,
      deleteWhenDone: true,
      platformErrorMessage: errorMessage is String ? errorMessage : null,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ExternalImportFileReference &&
        other.path == path &&
        other.displayName == displayName &&
        other.deleteWhenDone == deleteWhenDone &&
        other.platformErrorMessage == platformErrorMessage &&
        other.expectedSource == expectedSource;
  }

  @override
  int get hashCode => Object.hash(
    path,
    displayName,
    deleteWhenDone,
    platformErrorMessage,
    expectedSource,
  );
}
