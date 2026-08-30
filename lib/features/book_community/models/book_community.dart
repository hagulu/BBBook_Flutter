/// 책 상세/생각나눔 탭이 공유하는 커뮤니티 미리보기·개수 모델.
///
/// 문서: ../../../../../api-doc/api-books-isbn13-community-preview-get.md,
/// api-books-isbn13-community-counts-get.md
library;

/// 커뮤니티 미리보기의 최근 독자평 작성자(개인화 정보·완독 책장 공개 여부는
/// 응답에 없다).
class BookCommunityReviewAuthor {
  const BookCommunityReviewAuthor({
    required this.id,
    this.nickname,
    this.profileImageUrl,
  });

  final int id;
  final String? nickname;
  final String? profileImageUrl;

  factory BookCommunityReviewAuthor.fromJson(Map<String, dynamic> json) {
    return BookCommunityReviewAuthor(
      id: json['id'] as int,
      nickname: json['nickname'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
    );
  }
}

/// 커뮤니티 미리보기에 포함되는 최근 독자평 한 건(숨김·스포일러 제외, 최신순
/// 최대 3개). 읽기 전용이라 좋아요·수정·신고 상태를 담지 않는다.
class BookCommunityReviewPreview {
  const BookCommunityReviewPreview({
    required this.id,
    required this.user,
    this.rating,
    required this.content,
    required this.likeCount,
    required this.createdAt,
  });

  final int id;
  final BookCommunityReviewAuthor user;

  /// 0.0 ~ 5.0(전체 리뷰 API와 동일한 5점 만점 스케일).
  final double? rating;
  final String content;
  final int likeCount;
  final DateTime createdAt;

  factory BookCommunityReviewPreview.fromJson(Map<String, dynamic> json) {
    return BookCommunityReviewPreview(
      id: json['id'] as int,
      user: BookCommunityReviewAuthor.fromJson(
        json['user'] as Map<String, dynamic>,
      ),
      rating: (json['rating'] as num?)?.toDouble(),
      content: json['content'] as String,
      likeCount: json['likeCount'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// `GET /api/books/{isbn13}/community-preview` 응답.
///
/// `reflectionCount`/`discussionCount`는 community-counts 응답의
/// `reflectionCount`/`discussionCount`와 정의가 같은 값이라(각 API 문서
/// 기준), 독자평 전체 개수(`reviewCount`, 이 응답엔 없음)가 필요 없는
/// 화면은 이 값만으로 개수를 표시하고 community-counts를 따로 부르지
/// 않는다.
class BookCommunityPreview {
  const BookCommunityPreview({
    required this.averageRating,
    required this.reviewItems,
    required this.reflectionCount,
    required this.discussionCount,
  });

  /// 숨김 처리되지 않고 별점이 있는 전체 독자평의 평균(소수점 1자리). 대상이
  /// 없으면 null.
  final double? averageRating;
  final List<BookCommunityReviewPreview> reviewItems;
  final int reflectionCount;
  final int discussionCount;

  factory BookCommunityPreview.fromJson(Map<String, dynamic> json) {
    final reviews = json['reviews'] as Map<String, dynamic>;
    final reflections = json['reflections'] as Map<String, dynamic>;
    final discussions = json['discussions'] as Map<String, dynamic>;
    return BookCommunityPreview(
      averageRating: (reviews['averageRating'] as num?)?.toDouble(),
      reviewItems: (reviews['items'] as List<dynamic>)
          .map(
            (e) =>
                BookCommunityReviewPreview.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      reflectionCount: reflections['count'] as int,
      discussionCount: discussions['count'] as int,
    );
  }
}

/// `GET /api/books/{isbn13}/community-counts` 응답. 세 개수 모두 스포일러
/// 콘텐츠를 포함해서 집계한다.
class BookCommunityCounts {
  const BookCommunityCounts({
    required this.reviewCount,
    required this.reflectionCount,
    required this.discussionCount,
  });

  final int reviewCount;
  final int reflectionCount;
  final int discussionCount;

  factory BookCommunityCounts.fromJson(Map<String, dynamic> json) {
    return BookCommunityCounts(
      reviewCount: json['reviewCount'] as int,
      reflectionCount: json['reflectionCount'] as int,
      discussionCount: json['discussionCount'] as int,
    );
  }
}
