import '../../bookshelf/models/book_status.dart';

enum ExternalImportSource {
  bookJuk('BOOK_JUK', '북적북적'),
  bookmory('BOOKMORY', '북모리');

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
  final String? coverImageUrl;
  final DateTime? createdAt;
  final List<ExternalNoteImportItem> notes;
  final List<String> tags;
}

class ExternalImportParseResult {
  const ExternalImportParseResult({
    required this.source,
    required this.books,
    required this.discoveredBookCount,
    required this.skippedItemCount,
    required this.warningCount,
  });

  final ExternalImportSource source;
  final List<ExternalBookImportItem> books;
  final int discoveredBookCount;
  final int skippedItemCount;
  final int warningCount;

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
  });

  final String path;
  final String displayName;
  final bool deleteWhenDone;
  final String? platformErrorMessage;

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
        other.platformErrorMessage == platformErrorMessage;
  }

  @override
  int get hashCode =>
      Object.hash(path, displayName, deleteWhenDone, platformErrorMessage);
}
