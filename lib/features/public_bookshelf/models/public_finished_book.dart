/// `GET /api/users/{userId}/books/finished`의 목록 항목.
class PublicFinishedBook {
  const PublicFinishedBook({
    this.isbn13,
    this.title,
    this.author,
    this.publisher,
    this.statsTotalPages,
    this.displayTotalPages,
    this.coverImageUrl,
    this.category,
    this.myRating,
    required this.isMasterpiece,
    this.finishedAt,
  });

  final String? isbn13;
  final String? title;
  final String? author;
  final String? publisher;
  final int? statsTotalPages;
  final int? displayTotalPages;
  final String? coverImageUrl;
  final String? category;
  final double? myRating;
  final bool isMasterpiece;
  final DateTime? finishedAt;

  factory PublicFinishedBook.fromJson(Map<String, dynamic> json) {
    return PublicFinishedBook(
      isbn13: json['isbn13'] as String?,
      title: json['title'] as String?,
      author: json['author'] as String?,
      publisher: json['publisher'] as String?,
      statsTotalPages: json['statsTotalPages'] as int?,
      displayTotalPages: json['displayTotalPages'] as int?,
      coverImageUrl: json['coverImageUrl'] as String?,
      category: json['category'] as String?,
      myRating: (json['myRating'] as num?)?.toDouble(),
      isMasterpiece: json['isMasterpiece'] as bool? ?? false,
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
    );
  }
}

/// 완독 목록 커서 페이지. 커서는 `cursor`(id) + `cursorDate`(완독일) 둘을
/// 함께 넘겨야 한다(api-users-id-books-finished-get.md).
class PublicFinishedBooksPage {
  const PublicFinishedBooksPage({
    required this.items,
    required this.nextCursor,
    required this.nextCursorDate,
    required this.hasNext,
  });

  final List<PublicFinishedBook> items;
  final int? nextCursor;
  final DateTime? nextCursorDate;
  final bool hasNext;

  factory PublicFinishedBooksPage.fromJson(Map<String, dynamic> json) {
    return PublicFinishedBooksPage(
      items: (json['items'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                PublicFinishedBook.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      nextCursor: json['nextCursor'] as int?,
      nextCursorDate: json['nextCursorDate'] == null
          ? null
          : DateTime.parse(json['nextCursorDate'] as String),
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }
}
