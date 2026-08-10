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

  /// [tags]와 [updatedAt]만 다른 사본을 만든다. 태그 추가/삭제 응답이
  /// 태그 정보만 돌려주는 API(POST/DELETE tags)의 결과를 로컬 [BookItem]에
  /// 반영할 때 사용한다.
  BookItem copyWithTags(List<BookTag> tags, {required DateTime updatedAt}) {
    return BookItem(
      userBookId: userBookId,
      bookId: bookId,
      isbn13: isbn13,
      title: title,
      author: author,
      publisher: publisher,
      totalPages: totalPages,
      coverImageUrl: coverImageUrl,
      displayCategoryId: displayCategoryId,
      category: category,
      status: status,
      currentPage: currentPage,
      myRating: myRating,
      shortReview: shortReview,
      isMasterpiece: isMasterpiece,
      sourceType: sourceType,
      rereadCount: rereadCount,
      difficulty: difficulty,
      startedAt: startedAt,
      finishedAt: finishedAt,
      libraryId: libraryId,
      libraryDueAt: libraryDueAt,
      platformName: platformName,
      discoverySource: discoverySource,
      tags: tags,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory BookItem.fromSyncJson(Map<String, dynamic> json) {
    return BookItem.fromDetailJson(
      json,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// `PATCH /api/me/books/:userBookId`류 응답(책 기록 상세 데이터)에는
  /// `createdAt`/`updatedAt`이 내려오지 않는다. 로컬 DB의 `NOT NULL` 컬럼을
  /// 채우기 위해 호출 측이 기존 로컬 행의 [createdAt]을 그대로 넘기고,
  /// [updatedAt]은 응답을 반영하는 시점의 클라이언트 시각(UTC)을 넘긴다.
  factory BookItem.fromDetailJson(
    Map<String, dynamic> json, {
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
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
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.parse(value);
  }
}
