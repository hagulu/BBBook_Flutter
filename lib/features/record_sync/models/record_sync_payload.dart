import '../../bookshelf/models/book_item.dart';

class ServerBookNoteMemo {
  const ServerBookNoteMemo({
    required this.id,
    required this.noteId,
    required this.memoType,
    required this.startPage,
    required this.endPage,
    required this.content,
    required this.imageUrl,
    required this.isImportant,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServerBookNoteMemo.fromJson(Map<String, dynamic> json) {
    return ServerBookNoteMemo(
      id: json['id'] as int,
      noteId: json['noteId'] as int,
      memoType: json['memoType'] as String,
      startPage: json['startPage'] as int?,
      endPage: json['endPage'] as int?,
      content: json['content'] as String?,
      imageUrl: json['imageUrl'] as String?,
      isImportant: json['isImportant'] as bool,
      sortOrder: json['sortOrder'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      // GET /api/me/records 응답의 noteMemos[n]은 api-doc 기준
      // `GET /api/me/notes/sync/changes`의 upsertedNoteMemos[n]과 같은
      // 스키마라 updatedAt을 포함하지만, 혹시 누락돼도(구버전 서버 등)
      // createdAt으로 대체해 항상 값이 있게 한다 — 이후 증분 동기화가
      // 이 값을 변경 감지 기준으로 쓴다.
      updatedAt: json['updatedAt'] == null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.parse(json['updatedAt'] as String),
    );
  }

  final int id;
  final int noteId;
  final String memoType;
  final int? startPage;
  final int? endPage;
  final String? content;
  final String? imageUrl;
  final bool isImportant;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ServerBookNote {
  const ServerBookNote({
    required this.id,
    required this.userBookId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServerBookNote.fromJson(Map<String, dynamic> json) {
    return ServerBookNote(
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

class ServerTag {
  const ServerTag({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServerTag.fromJson(Map<String, dynamic> json) {
    return ServerTag(
      id: json['id'] as int,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ServerTagMap {
  const ServerTagMap({
    required this.id,
    required this.userBookId,
    required this.tagId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServerTagMap.fromJson(Map<String, dynamic> json) {
    return ServerTagMap(
      id: json['id'] as int,
      userBookId: json['userBookId'] as int,
      tagId: json['tagId'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final int id;
  final int userBookId;
  final int tagId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class RecordSyncPayload {
  const RecordSyncPayload({
    required this.books,
    required this.notes,
    required this.noteMemos,
    required this.reflections,
    required this.tags,
    required this.tagMaps,
  });

  factory RecordSyncPayload.fromJson(Map<String, dynamic> json) {
    final payload = RecordSyncPayload(
      books: (json['books'] as List<dynamic>)
          .map((book) => BookItem.fromSyncJson(book as Map<String, dynamic>))
          .toList(growable: false),
      notes: (json['notes'] as List<dynamic>)
          .map((note) => ServerBookNote.fromJson(note as Map<String, dynamic>))
          .toList(growable: false),
      noteMemos: (json['noteMemos'] as List<dynamic>)
          .map(
            (memo) => ServerBookNoteMemo.fromJson(memo as Map<String, dynamic>),
          )
          .toList(growable: false),
      reflections: (json['reflections'] as List<dynamic>)
          .map(
            (reflection) => ServerBookReflection.fromJson(
              reflection as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
      tags: (json['tags'] as List<dynamic>)
          .map((tag) => ServerTag.fromJson(tag as Map<String, dynamic>))
          .toList(growable: false),
      tagMaps: (json['tagMaps'] as List<dynamic>)
          .map((map) => ServerTagMap.fromJson(map as Map<String, dynamic>))
          .toList(growable: false),
    );
    payload._validateRelationships();
    return payload;
  }

  final List<BookItem> books;
  final List<ServerBookNote> notes;
  final List<ServerBookNoteMemo> noteMemos;
  final List<ServerBookReflection> reflections;

  /// 태그/매핑은 `notes`/`noteMemos`와 달리 [_validateRelationships]에서
  /// 검사하지 않는다 — 단일 태그 매핑의 FK 불일치(상위 책이 이번 응답에
  /// 없는 등, `TagDao`가 orphan으로 로그만 남기고 건너뛰는 경우) 하나 때문에
  /// 책장·노트·독후감까지 포함한 전체 최초 동기화가 통째로 실패해서는 안
  /// 된다.
  final List<ServerTag> tags;
  final List<ServerTagMap> tagMaps;

  int get totalItemCount =>
      books.length +
      notes.length +
      noteMemos.length +
      reflections.length +
      tags.length +
      tagMaps.length;

  void _validateRelationships() {
    final bookIds = books.map((book) => book.userBookId).toSet();
    final noteIds = notes.map((note) => note.id).toSet();
    final noteMemoIds = noteMemos.map((memo) => memo.id).toSet();
    final reflectionIds = reflections
        .map((reflection) => reflection.id)
        .toSet();
    if (bookIds.length != books.length ||
        noteIds.length != notes.length ||
        noteMemoIds.length != noteMemos.length ||
        reflectionIds.length != reflections.length ||
        notes.any((note) => !bookIds.contains(note.userBookId)) ||
        reflections.any(
          (reflection) => !bookIds.contains(reflection.userBookId),
        ) ||
        noteMemos.any((memo) => !noteIds.contains(memo.noteId))) {
      throw const FormatException('Invalid record relationships');
    }
  }
}
