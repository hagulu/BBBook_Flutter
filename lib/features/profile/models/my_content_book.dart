/// "내가 작성한 콘텐츠" 4개 목록(`my-content-screens.md`)이 공유하는 책 요약.
///
/// 책 정보를 찾을 수 없으면 서버 응답 자체가 `book: null`이다.
class MyContentBookRef {
  const MyContentBookRef({required this.title, this.author, this.coverImageUrl});

  final String title;
  final String? author;
  final String? coverImageUrl;

  factory MyContentBookRef.fromJson(Map<String, dynamic> json) {
    return MyContentBookRef(
      title: json['title'] as String? ?? '',
      author: json['author'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
    );
  }
}

MyContentBookRef? myContentBookRefOrNullFromJson(dynamic json) {
  if (json is! Map<String, dynamic>) return null;
  return MyContentBookRef.fromJson(json);
}

/// 4개 목록이 공유하는 커서 페이지.
class MyContentPage<T> {
  const MyContentPage({
    required this.items,
    required this.nextCursor,
    required this.hasNext,
  });

  final List<T> items;
  final int? nextCursor;
  final bool hasNext;

  factory MyContentPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> item) itemFromJson,
  ) {
    return MyContentPage<T>(
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((item) => itemFromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      nextCursor: json['nextCursor'] as int?,
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }
}
