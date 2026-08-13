/// 리뷰 작성자 정보(`GET /api/books/{isbn13}/reviews` 응답 `user` 객체).
class ReviewAuthor {
  const ReviewAuthor({
    required this.id,
    this.nickname,
    this.profileImageUrl,
    required this.isFinishedBooksPublic,
  });

  final int id;
  final String? nickname;
  final String? profileImageUrl;
  final bool isFinishedBooksPublic;

  factory ReviewAuthor.fromJson(Map<String, dynamic> json) {
    return ReviewAuthor(
      id: json['id'] as int,
      nickname: json['nickname'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      isFinishedBooksPublic: json['isFinishedBooksPublic'] as bool? ?? false,
    );
  }
}

/// 책 상세 커뮤니티 리뷰 한 건. api-doc: api-books-isbn13-reviews-get.md 기준.
class BookReview {
  const BookReview({
    required this.id,
    required this.isbn13,
    required this.user,
    this.rating,
    this.content,
    required this.isSpoiler,
    required this.isHidden,
    required this.isMine,
    required this.likeCount,
    required this.isLiked,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String isbn13;
  final ReviewAuthor user;

  /// 0.0 ~ 5.0(리뷰 별점은 검색/상세와 달리 이미 5점 만점 스케일).
  final double? rating;
  final String? content;
  final bool isSpoiler;
  final bool isHidden;
  final bool isMine;
  final int likeCount;
  final bool isLiked;
  final DateTime createdAt;
  final DateTime updatedAt;

  BookReview copyWith({
    double? rating,
    bool clearRating = false,
    String? content,
    bool? isSpoiler,
    int? likeCount,
    bool? isLiked,
    DateTime? updatedAt,
  }) {
    return BookReview(
      id: id,
      isbn13: isbn13,
      user: user,
      rating: clearRating ? null : (rating ?? this.rating),
      content: content ?? this.content,
      isSpoiler: isSpoiler ?? this.isSpoiler,
      isHidden: isHidden,
      isMine: isMine,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory BookReview.fromJson(Map<String, dynamic> json) {
    return BookReview(
      id: json['id'] as int,
      isbn13: json['isbn13'] as String,
      user: ReviewAuthor.fromJson(json['user'] as Map<String, dynamic>),
      rating: (json['rating'] as num?)?.toDouble(),
      content: json['content'] as String?,
      isSpoiler: json['isSpoiler'] as bool,
      isHidden: json['isHidden'] as bool,
      isMine: json['isMine'] as bool,
      likeCount: json['likeCount'] as int,
      isLiked: json['isLiked'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// `GET /api/books/{isbn13}/reviews` 커서 기반 목록 페이지.
class ReviewsPage {
  const ReviewsPage({
    required this.items,
    required this.nextCursor,
    required this.hasNext,
  });

  final List<BookReview> items;
  final int? nextCursor;
  final bool hasNext;

  factory ReviewsPage.fromJson(Map<String, dynamic> json) {
    return ReviewsPage(
      items: (json['items'] as List<dynamic>)
          .map((e) => BookReview.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as int?,
      hasNext: json['hasNext'] as bool,
    );
  }
}
