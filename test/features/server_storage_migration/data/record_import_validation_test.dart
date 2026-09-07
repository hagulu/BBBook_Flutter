import 'package:bbbook/features/book_note/models/book_note.dart';
import 'package:bbbook/features/book_reflection/models/book_reflection.dart';
import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/server_storage_migration/data/record_import_snapshot.dart';
import 'package:bbbook/features/server_storage_migration/data/record_import_validation.dart';
import 'package:bbbook/features/tag/models/tag_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

BookItem _book({
  int userBookId = -1,
  String? clientRequestId = 'book-crid',
  String title = '책 제목',
  String? shortReview,
  int currentPage = 10,
  int? statsTotalPages,
  int? displayTotalPages,
  String? sourceType,
  double? myRating,
}) {
  return BookItem(
    userBookId: userBookId,
    clientRequestId: clientRequestId,
    title: title,
    status: BookStatus.reading,
    currentPage: currentPage,
    statsTotalPages: statsTotalPages,
    displayTotalPages: displayTotalPages,
    sourceType: sourceType,
    myRating: myRating,
    shortReview: shortReview,
    isMasterpiece: false,
    rereadCount: 0,
    tags: const [],
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
  );
}

BookNote _note({
  int id = -1,
  int? serverId,
  String? title,
  int userBookId = -1,
}) {
  return BookNote(
    id: id,
    serverId: serverId,
    userBookId: userBookId,
    title: title,
    deletedAt: null,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    isDirty: true,
  );
}

BookNoteMemo _memo({
  int id = -1,
  String? clientRequestId = 'memo-crid',
  int noteId = -1,
  int? startPage,
  int? endPage,
  int sortOrder = 0,
}) {
  return BookNoteMemo(
    id: id,
    serverId: null,
    clientRequestId: clientRequestId,
    noteId: noteId,
    type: BookNoteMemoType.quote,
    startPage: startPage,
    endPage: endPage,
    content: '내용',
    imageUrl: null,
    localImagePath: null,
    isImportant: false,
    sortOrder: sortOrder,
    deletedAt: null,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    isDirty: true,
  );
}

ReflectionForImport _reflection({
  int id = -1,
  String? clientRequestId = 'reflection-crid',
  String? title = '제목',
  String? contentText = '본문',
}) {
  final reflection = BookReflection(
    id: id,
    serverId: null,
    clientRequestId: clientRequestId,
    userBookId: -1,
    reflectionType: 'USER_WRITTEN',
    title: title,
    contentJson: const {
      'ops': [
        {'insert': '\n'},
      ],
    },
    contentText: contentText,
    isPublic: false,
    isHidden: false,
    deletedAt: null,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    isDirty: true,
  );
  return ReflectionForImport(
    reflection: reflection,
    contentJsonForImport: reflection.contentJson!,
  );
}

LocalTag _tag({int id = -1, String name = '태그'}) {
  return LocalTag(id: id, serverId: null, name: name);
}

TagMapping _tagMap({int id = -1, int userBookId = -1, int tagId = -1}) {
  return TagMapping(
    id: id,
    serverId: null,
    userBookId: userBookId,
    tagId: tagId,
    deletedAt: null,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    isDirty: true,
  );
}

String? _validate({
  List<BookItem> books = const [],
  List<BookNote> notes = const [],
  List<BookNoteMemo> memos = const [],
  List<ReflectionForImport> reflections = const [],
  List<LocalTag> tags = const [],
  List<TagMapping> tagMaps = const [],
}) {
  return validateRecordImportSnapshot(
    books: books,
    notes: notes,
    memos: memos,
    reflections: reflections,
    tags: tags,
    tagMaps: tagMaps,
  );
}

void main() {
  test('모두 정상이면 통과한다', () {
    expect(_validate(books: [_book()]), isNull);
  });

  test('한줄평이 150자를 넘으면 거부한다', () {
    expect(_validate(books: [_book(shortReview: 'a' * 151)]), isNotNull);
  });

  test('진행 쪽수가 총 쪽수를 넘으면 거부한다', () {
    expect(
      _validate(books: [_book(currentPage: 101, statsTotalPages: 100)]),
      isNotNull,
    );
  });

  test('오디오북은 진행 쪽수를 0~100 진행률로 보고 100을 넘으면 거부한다', () {
    expect(
      _validate(
        books: [_book(currentPage: 101, sourceType: 'AUDIO_BOOK')],
      ),
      isNotNull,
    );
    expect(
      _validate(books: [_book(currentPage: 100, sourceType: 'AUDIO_BOOK')]),
      isNull,
    );
  });

  test('별점이 범위를 벗어나면 거부한다', () {
    expect(_validate(books: [_book(myRating: 5.5)]), isNotNull);
  });

  test('책의 clientRequestId가 중복되면 거부한다', () {
    expect(
      _validate(
        books: [
          _book(userBookId: -1, clientRequestId: 'dup'),
          _book(userBookId: -2, clientRequestId: 'dup'),
        ],
      ),
      isNotNull,
    );
  });

  test('메모 없고 제목도 없는 신규 노트는 거부한다', () {
    expect(_validate(notes: [_note(title: null)]), isNotNull);
  });

  test('메모가 있으면 제목 없는 노트도 통과한다', () {
    expect(
      _validate(
        notes: [_note(id: -1, title: null)],
        memos: [_memo(noteId: -1)],
      ),
      isNull,
    );
  });

  test('기존 서버 노트(serverId 있음)는 제목 없어도 통과한다', () {
    expect(_validate(notes: [_note(serverId: 10, title: null)]), isNull);
  });

  test('메모의 시작 쪽수가 끝 쪽수보다 크면 거부한다', () {
    expect(_validate(memos: [_memo(startPage: 10, endPage: 5)]), isNotNull);
  });

  test('메모 clientRequestId가 중복되면 거부한다', () {
    expect(
      _validate(
        memos: [
          _memo(id: -1, clientRequestId: 'dup'),
          _memo(id: -2, clientRequestId: 'dup'),
        ],
      ),
      isNotNull,
    );
  });

  test('제목이나 본문이 없는 독후감은 거부한다', () {
    expect(_validate(reflections: [_reflection(title: null)]), isNotNull);
    expect(_validate(reflections: [_reflection(contentText: null)]), isNotNull);
  });

  test('독후감 clientRequestId가 중복되면 거부한다', () {
    expect(
      _validate(
        reflections: [
          _reflection(id: -1, clientRequestId: 'dup'),
          _reflection(id: -2, clientRequestId: 'dup'),
        ],
      ),
      isNotNull,
    );
  });

  test('태그 이름이 15자를 넘으면 거부한다', () {
    expect(_validate(tags: [_tag(name: '가' * 16)]), isNotNull);
  });

  test('같은 이름의 태그가 둘 이상이면 거부한다(서버 findOrCreate 1:1 위반)', () {
    expect(
      _validate(
        tags: [_tag(id: -1, name: '중복'), _tag(id: -2, name: '중복')],
      ),
      isNotNull,
    );
  });

  test('같은 (userBookId, tagId) 매핑이 중복되면 거부한다', () {
    expect(
      _validate(
        tagMaps: [
          _tagMap(id: -1, userBookId: -1, tagId: -1),
          _tagMap(id: -2, userBookId: -1, tagId: -1),
        ],
      ),
      isNotNull,
    );
  });

  test('한 책에 활성 태그 매핑이 11개면 거부한다', () {
    final maps = List.generate(
      11,
      (i) => _tagMap(id: -(i + 1), userBookId: -1, tagId: -(i + 1)),
    );
    expect(_validate(tagMaps: maps), isNotNull);
  });

  test('한 책에 활성 태그 매핑이 10개면 통과한다', () {
    final maps = List.generate(
      10,
      (i) => _tagMap(id: -(i + 1), userBookId: -1, tagId: -(i + 1)),
    );
    expect(_validate(tagMaps: maps), isNull);
  });
}
