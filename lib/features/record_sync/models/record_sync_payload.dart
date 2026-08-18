import '../../bookshelf/models/book_item.dart';

class ServerBookMemoItem {
  const ServerBookMemoItem({
    required this.id,
    required this.memoId,
    required this.itemType,
    required this.startPage,
    required this.endPage,
    required this.content,
    required this.imageUrl,
    required this.isImportant,
    required this.sortOrder,
    required this.createdAt,
  });

  factory ServerBookMemoItem.fromJson(Map<String, dynamic> json) {
    return ServerBookMemoItem(
      id: json['id'] as int,
      memoId: json['memoId'] as int,
      itemType: json['itemType'] as String,
      startPage: json['startPage'] as int?,
      endPage: json['endPage'] as int?,
      content: json['content'] as String?,
      imageUrl: json['imageUrl'] as String?,
      isImportant: json['isImportant'] as bool,
      sortOrder: json['sortOrder'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final int id;
  final int memoId;
  final String itemType;
  final int? startPage;
  final int? endPage;
  final String? content;
  final String? imageUrl;
  final bool isImportant;
  final int sortOrder;
  final DateTime createdAt;
}

class ServerBookMemo {
  const ServerBookMemo({
    required this.id,
    required this.userBookId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServerBookMemo.fromJson(Map<String, dynamic> json) {
    return ServerBookMemo(
      id: json['id'] as int,
      userBookId: json['userBookId'] as int,
      title: json['title'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final int id;
  final int userBookId;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ServerBookReflection {
  const ServerBookReflection({
    required this.id,
    required this.userBookId,
    required this.reflectionType,
    required this.title,
    required this.contentJson,
    required this.contentText,
    required this.isPublic,
    required this.isHidden,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServerBookReflection.fromJson(Map<String, dynamic> json) {
    return ServerBookReflection(
      id: json['id'] as int,
      userBookId: json['userBookId'] as int,
      reflectionType: json['reflectionType'] as String,
      title: json['title'] as String?,
      contentJson: json['contentJson'] as Map<String, dynamic>?,
      contentText: json['contentText'] as String?,
      isPublic: json['isPublic'] as bool,
      isHidden: json['isHidden'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final int id;
  final int userBookId;
  final String reflectionType;
  final String? title;
  final Map<String, dynamic>? contentJson;
  final String? contentText;
  final bool isPublic;
  final bool isHidden;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class RecordSyncPayload {
  const RecordSyncPayload({
    required this.books,
    required this.memos,
    required this.items,
    required this.reflections,
  });

  factory RecordSyncPayload.fromJson(Map<String, dynamic> json) {
    final payload = RecordSyncPayload(
      books: (json['books'] as List<dynamic>)
          .map((book) => BookItem.fromSyncJson(book as Map<String, dynamic>))
          .toList(growable: false),
      memos: (json['memos'] as List<dynamic>)
          .map((memo) => ServerBookMemo.fromJson(memo as Map<String, dynamic>))
          .toList(growable: false),
      items: (json['items'] as List<dynamic>)
          .map(
            (item) => ServerBookMemoItem.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      reflections: (json['reflections'] as List<dynamic>)
          .map(
            (reflection) => ServerBookReflection.fromJson(
              reflection as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
    );
    payload._validateRelationships();
    return payload;
  }

  final List<BookItem> books;
  final List<ServerBookMemo> memos;
  final List<ServerBookMemoItem> items;
  final List<ServerBookReflection> reflections;

  int get totalItemCount =>
      books.length + memos.length + items.length + reflections.length;

  void _validateRelationships() {
    final bookIds = books.map((book) => book.userBookId).toSet();
    final memoIds = memos.map((memo) => memo.id).toSet();
    final itemIds = items.map((item) => item.id).toSet();
    final reflectionIds = reflections
        .map((reflection) => reflection.id)
        .toSet();
    if (bookIds.length != books.length ||
        memoIds.length != memos.length ||
        itemIds.length != items.length ||
        reflectionIds.length != reflections.length ||
        memos.any((memo) => !bookIds.contains(memo.userBookId)) ||
        reflections.any(
          (reflection) => !bookIds.contains(reflection.userBookId),
        ) ||
        items.any((item) => !memoIds.contains(item.memoId))) {
      throw const FormatException('Invalid record relationships');
    }
  }
}
