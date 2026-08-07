import 'book_status.dart';
import 'book_tag.dart';

/// 책장의 책 한 권. `GET /api/me/books/sync` 응답 및 로컬 DB(`user_book` 테이블) 공용 모델.
class BookItem {
  const BookItem({
    required this.userBookId,
    this.bookId,
    this.isbn13,
    required this.title,
    this.author,
    this.publisher,
    this.totalPages,
    this.coverImageUrl,
    this.displayCategoryId,
    this.category,
    required this.status,
    required this.currentPage,
    this.myRating,
    this.shortReview,
    required this.isMasterpiece,
    this.sourceType,
    required this.rereadCount,
    this.difficulty,
    this.startedAt,
    this.finishedAt,
    this.libraryId,
    this.libraryDueAt,
    this.platformName,
    this.discoverySource,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
  });

  final int userBookId;
  final int? bookId;
  final String? isbn13;
  final String title;
  final String? author;
  final String? publisher;
  final int? totalPages;
  final String? coverImageUrl;
  final int? displayCategoryId;
  final String? category;
  final BookStatus status;
  final int currentPage;
  final double? myRating;
  final String? shortReview;
  final bool isMasterpiece;
  final String? sourceType;
  final int rereadCount;
  final String? difficulty;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? libraryId;
  final DateTime? libraryDueAt;
  final String? platformName;
  final String? discoverySource;
  final List<BookTag> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 0.0 ~ 1.0. totalPages를 모르면 null(진행률 표시 불가).
  double? get progressRatio {
    final total = totalPages;
    if (total == null || total <= 0) return null;
    return (currentPage / total).clamp(0.0, 1.0);
  }

  factory BookItem.fromSyncJson(Map<String, dynamic> json) {
    return BookItem(
      userBookId: json['userBookId'] as int,
      bookId: json['bookId'] as int?,
      isbn13: json['isbn13'] as String?,
      title: json['title'] as String,
      author: json['author'] as String?,
      publisher: json['publisher'] as String?,
      totalPages: json['totalPages'] as int?,
      coverImageUrl: json['coverImageUrl'] as String?,
      displayCategoryId: json['displayCategoryId'] as int?,
      category: json['category'] as String?,
      status: BookStatus.fromApiValue(json['status'] as String),
      currentPage: json['currentPage'] as int,
      myRating: (json['myRating'] as num?)?.toDouble(),
      shortReview: json['shortReview'] as String?,
      isMasterpiece: json['isMasterpiece'] as bool,
      sourceType: json['sourceType'] as String?,
      rereadCount: json['rereadCount'] as int,
      difficulty: json['difficulty'] as String?,
      startedAt: _parseDate(json['startedAt'] as String?),
      finishedAt: _parseDate(json['finishedAt'] as String?),
      libraryId: json['libraryId'] as int?,
      libraryDueAt: _parseDate(json['libraryDueAt'] as String?),
      platformName: json['platformName'] as String?,
      discoverySource: json['discoverySource'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => BookTag.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.parse(value);
  }
}
