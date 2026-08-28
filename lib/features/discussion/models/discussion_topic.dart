/// 토론 작성자/답변 작성자 정보(응답 `user` 객체).
class DiscussionAuthor {
  const DiscussionAuthor({
    required this.id,
    this.nickname,
    this.profileImageUrl,
    required this.isFinishedBooksPublic,
  });

  final int id;
  final String? nickname;
  final String? profileImageUrl;
  final bool isFinishedBooksPublic;

  factory DiscussionAuthor.fromJson(Map<String, dynamic> json) {
    return DiscussionAuthor(
      id: json['id'] as int,
      nickname: json['nickname'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      isFinishedBooksPublic: json['isFinishedBooksPublic'] as bool? ?? false,
    );
  }
}

/// 토론 상세에 연결된 책 정보(`GET /api/discussions/{topicId}` 응답 `book`).
class DiscussionBook {
  const DiscussionBook({required this.title, this.author, this.coverImageUrl});

  final String title;
  final String? author;
  final String? coverImageUrl;

  factory DiscussionBook.fromJson(Map<String, dynamic> json) {
    return DiscussionBook(
      title: json['title'] as String? ?? '',
      author: json['author'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
    );
  }
}

/// 선택지 한 개. 목록/작성 응답에는 집계값이 없어 [voteCount]/[votePercentage]는
/// 상세 조회에서만 채워진다.
class DiscussionOption {
  const DiscussionOption({
    required this.id,
    required this.content,
    required this.sortOrder,
    this.voteCount = 0,
    this.votePercentage = 0,
  });

  final int id;
  final String content;
  final int sortOrder;
  final int voteCount;
  final double votePercentage;

  factory DiscussionOption.fromJson(Map<String, dynamic> json) {
    return DiscussionOption(
      id: json['id'] as int,
      content: json['content'] as String? ?? '',
      sortOrder: json['sortOrder'] as int? ?? 0,
      voteCount: json['voteCount'] as int? ?? 0,
      votePercentage: (json['votePercentage'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// 토론 주제 목록 카드 한 건(`GET /api/books/{isbn13}/discussions`).
class DiscussionTopic {
  const DiscussionTopic({
    required this.id,
    required this.isbn13,
    required this.user,
    this.title,
    this.content,
    required this.isSpoiler,
    required this.isHidden,
    this.closesAt,
    this.closedAt,
    required this.isClosed,
    required this.likeCount,
    required this.likedByMe,
    required this.isMine,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String isbn13;
  final DiscussionAuthor user;

  /// 숨김 처리(`isHidden`)된 주제는 서버가 제목·본문을 null로 내려준다.
  final String? title;
  final String? content;
  final bool isSpoiler;
  final bool isHidden;
  final DateTime? closesAt;
  final DateTime? closedAt;
  final bool isClosed;
  final int likeCount;
  final bool likedByMe;
  final bool isMine;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory DiscussionTopic.fromJson(Map<String, dynamic> json) {
    return DiscussionTopic(
      id: json['id'] as int,
      isbn13: json['isbn13'] as String? ?? '',
      user: DiscussionAuthor.fromJson(json['user'] as Map<String, dynamic>),
      title: json['title'] as String?,
      content: json['content'] as String?,
      isSpoiler: json['isSpoiler'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      closesAt: parseNullableDate(json['closesAt']),
      closedAt: parseNullableDate(json['closedAt']),
      isClosed: json['isClosed'] as bool? ?? false,
      likeCount: json['likeCount'] as int? ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
      isMine: json['isMine'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// 토론 주제 상세(`GET /api/discussions/{topicId}`). 목록 항목에 책 정보와
/// 선택지 집계가 더해진 형태다.
class DiscussionTopicDetail {
  const DiscussionTopicDetail({
    required this.id,
    required this.isbn13,
    required this.book,
    required this.user,
    this.title,
    this.content,
    required this.isSpoiler,
    this.closesAt,
    this.closedAt,
    required this.isClosed,
    required this.likeCount,
    required this.likedByMe,
    required this.isMine,
    required this.options,
    required this.otherVoteCount,
    required this.otherVotePercentage,
    required this.totalVoteCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String isbn13;
  final DiscussionBook book;
  final DiscussionAuthor user;
  final String? title;
  final String? content;
  final bool isSpoiler;
  final DateTime? closesAt;
  final DateTime? closedAt;
  final bool isClosed;
  final int likeCount;
  final bool likedByMe;
  final bool isMine;

  /// `sortOrder` 오름차순으로 정렬된 선택지. 자유 토론이면 비어 있다.
  final List<DiscussionOption> options;
  final int otherVoteCount;
  final double otherVotePercentage;
  final int totalVoteCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 선택지 토론 여부. 자유 토론과 화면 구성이 갈리는 기준이다.
  bool get hasOptions => options.isNotEmpty;

  /// 작성자가 직접 닫은 토론만 다시 열 수 있다(마감일 자동 만료는 불가).
  bool get canReopen => isMine && closedAt != null;

  DiscussionTopicDetail copyWith({
    bool? likedByMe,
    int? likeCount,
    Object? closesAt = _unset,
    Object? closedAt = _unset,
    bool? isClosed,
  }) {
    return DiscussionTopicDetail(
      id: id,
      isbn13: isbn13,
      book: book,
      user: user,
      title: title,
      content: content,
      isSpoiler: isSpoiler,
      closesAt: closesAt == _unset ? this.closesAt : closesAt as DateTime?,
      closedAt: closedAt == _unset ? this.closedAt : closedAt as DateTime?,
      isClosed: isClosed ?? this.isClosed,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      isMine: isMine,
      options: options,
      otherVoteCount: otherVoteCount,
      otherVotePercentage: otherVotePercentage,
      totalVoteCount: totalVoteCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory DiscussionTopicDetail.fromJson(Map<String, dynamic> json) {
    final options =
        (json['options'] as List<dynamic>? ?? const [])
            .map((e) => DiscussionOption.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return DiscussionTopicDetail(
      id: json['id'] as int,
      isbn13: json['isbn13'] as String? ?? '',
      book: DiscussionBook.fromJson(
        json['book'] as Map<String, dynamic>? ?? const {},
      ),
      user: DiscussionAuthor.fromJson(json['user'] as Map<String, dynamic>),
      title: json['title'] as String?,
      content: json['content'] as String?,
      isSpoiler: json['isSpoiler'] as bool? ?? false,
      closesAt: parseNullableDate(json['closesAt']),
      closedAt: parseNullableDate(json['closedAt']),
      isClosed: json['isClosed'] as bool? ?? false,
      likeCount: json['likeCount'] as int? ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
      isMine: json['isMine'] as bool? ?? false,
      options: options,
      otherVoteCount: json['otherVoteCount'] as int? ?? 0,
      otherVotePercentage:
          (json['otherVotePercentage'] as num?)?.toDouble() ?? 0,
      totalVoteCount: json['totalVoteCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

const _unset = Object();

/// `GET /api/books/{isbn13}/discussions` 커서 기반 목록 페이지.
class DiscussionTopicsPage {
  const DiscussionTopicsPage({
    required this.items,
    required this.nextCursor,
    required this.hasNext,
  });

  final List<DiscussionTopic> items;
  final int? nextCursor;
  final bool hasNext;

  factory DiscussionTopicsPage.fromJson(Map<String, dynamic> json) {
    return DiscussionTopicsPage(
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => DiscussionTopic.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as int?,
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }
}

DateTime? parseNullableDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
