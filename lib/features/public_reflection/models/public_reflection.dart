/// 공개 독후감 작성자 정보.
class PublicReflectionAuthor {
  const PublicReflectionAuthor({
    required this.id,
    this.nickname,
    this.profileImageUrl,
  });

  final int id;
  final String? nickname;
  final String? profileImageUrl;

  factory PublicReflectionAuthor.fromJson(Map<String, dynamic> json) {
    return PublicReflectionAuthor(
      id: json['id'] as int,
      nickname: json['nickname'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
    );
  }

  /// 공개 독후감 API는 현재 문서의 `user` 객체 형식과 레거시 flat 형식
  /// (`userId`, `nickname`, `profileImageUrl`)이 함께 존재한다. 기존 웹과
  /// 동일하게 두 응답을 하나의 작성자 모델로 정규화한다.
  factory PublicReflectionAuthor.fromContainerJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    if (rawUser is Map) {
      return PublicReflectionAuthor.fromJson(
        Map<String, dynamic>.from(rawUser),
      );
    }
    return PublicReflectionAuthor(
      id: json['userId'] as int? ?? 0,
      nickname: json['nickname'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
    );
  }
}

/// `GET /api/books/{isbn13}/reflections`의 목록 항목.
class PublicReflectionSummary {
  const PublicReflectionSummary({
    required this.id,
    required this.title,
    required this.contentText,
    required this.isHidden,
    required this.user,
    required this.createdAt,
    required this.updatedAt,
    this.likeCount = 0,
  });

  final int id;
  final String? title;
  final String? contentText;

  /// 서버가 숨김 항목을 내려주더라도 서비스 계층에서 목록에서 제거한다.
  final bool isHidden;
  final PublicReflectionAuthor user;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int likeCount;

  factory PublicReflectionSummary.fromJson(Map<String, dynamic> json) {
    return PublicReflectionSummary(
      id: json['id'] as int,
      title: json['title'] as String?,
      contentText: json['contentText'] as String?,
      isHidden: json['isHidden'] as bool? ?? false,
      user: PublicReflectionAuthor.fromContainerJson(json),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      likeCount: json['likeCount'] as int? ?? 0,
    );
  }
}

/// 공개 독후감 커서 페이지.
class PublicReflectionsPage {
  const PublicReflectionsPage({
    required this.items,
    required this.nextCursor,
    required this.hasNext,
  });

  final List<PublicReflectionSummary> items;
  final int? nextCursor;
  final bool hasNext;

  factory PublicReflectionsPage.fromJson(Map<String, dynamic> json) {
    return PublicReflectionsPage(
      items: (json['items'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                PublicReflectionSummary.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      nextCursor: json['nextCursor'] as int?,
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }
}

/// 공개 독후감 상세에 포함된 책 정보.
class PublicReflectionBook {
  const PublicReflectionBook({
    required this.title,
    this.author,
    this.coverImageUrl,
  });

  final String title;
  final String? author;
  final String? coverImageUrl;

  factory PublicReflectionBook.fromJson(Map<String, dynamic> json) {
    return PublicReflectionBook(
      title: json['title'] as String? ?? '',
      author: json['author'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
    );
  }
}

/// `GET /api/reflections/{reflectionId}`의 리더 화면 데이터.
class PublicReflectionDetail {
  const PublicReflectionDetail({
    required this.id,
    required this.isbn13,
    required this.book,
    required this.title,
    required this.contentJson,
    required this.contentText,
    required this.isPublic,
    required this.status,
    required this.user,
    required this.createdAt,
    required this.updatedAt,
    this.likeCount = 0,
    this.likedByMe = false,
  });

  final int id;
  final String isbn13;
  final PublicReflectionBook book;
  final String title;
  final Map<String, dynamic> contentJson;
  final String contentText;
  final bool isPublic;
  final String status;
  final PublicReflectionAuthor user;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int likeCount;
  final bool likedByMe;

  bool get isPublished => status == 'PUBLISHED';

  PublicReflectionDetail copyWith({int? likeCount, bool? likedByMe}) {
    return PublicReflectionDetail(
      id: id,
      isbn13: isbn13,
      book: book,
      title: title,
      contentJson: contentJson,
      contentText: contentText,
      isPublic: isPublic,
      status: status,
      user: user,
      createdAt: createdAt,
      updatedAt: updatedAt,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
    );
  }

  factory PublicReflectionDetail.fromJson(Map<String, dynamic> json) {
    return PublicReflectionDetail(
      id: json['id'] as int,
      isbn13: json['isbn13'] as String,
      book: PublicReflectionBook.fromJson(
        json['book'] as Map<String, dynamic>? ?? const {},
      ),
      title: json['title'] as String,
      contentJson: Map<String, dynamic>.from(
        json['contentJson'] as Map<dynamic, dynamic>,
      ),
      contentText: json['contentText'] as String? ?? '',
      isPublic: json['isPublic'] as bool? ?? false,
      status: json['status'] as String? ?? '',
      user: PublicReflectionAuthor.fromContainerJson(json),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      likeCount: json['likeCount'] as int? ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
    );
  }
}
