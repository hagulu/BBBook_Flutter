import 'package:bbbook/features/book_note/models/book_note.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/server_storage_migration/data/record_import_payload_builder.dart';
import 'package:bbbook/features/tag/models/tag_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

BookItem _book({
  int userBookId = -1,
  int? serverId,
  String? clientRequestId = 'crid-1',
  String? coverImageUrl,
}) {
  return BookItem(
    userBookId: userBookId,
    serverId: serverId,
    clientRequestId: clientRequestId,
    title: '책 제목',
    status: BookStatus.reading,
    currentPage: 10,
    isMasterpiece: false,
    rereadCount: 0,
    coverImageUrl: coverImageUrl,
    tags: const [],
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
  );
}

void main() {
  group('bookToImportJson', () {
    test('원격 URL 표지는 그대로 보낸다', () {
      final json = bookToImportJson(
        _book(coverImageUrl: 'https://cdn.example.com/cover.jpg'),
      );
      expect(json['coverImageUrl'], 'https://cdn.example.com/cover.jpg');
    });

    test('로컬 파일 경로 표지는 null로 보낸다(§ 사용자 확인 — 표지 없이 Import)', () {
      final json = bookToImportJson(_book(coverImageUrl: 'book_covers/local_1.jpg'));
      expect(json['coverImageUrl'], isNull);
    });

    test('localId/serverId/clientRequestId를 그대로 옮긴다', () {
      final json = bookToImportJson(_book(userBookId: -5, serverId: 101));
      expect(json['localId'], -5);
      expect(json['serverId'], 101);
      expect(json['clientRequestId'], 'crid-1');
    });
  });

  group('noteMemoToImportJson', () {
    test('PHOTO 메모는 항상 imageUrl을 null로 보낸다(로컬 사진을 다시 올린다)', () {
      final memo = BookNoteMemo(
        id: -1,
        serverId: null,
        clientRequestId: 'memo-crid',
        noteId: -1,
        type: BookNoteMemoType.photo,
        startPage: null,
        endPage: null,
        content: null,
        imageUrl: 'https://old.example.com/stale.jpg',
        localImagePath: 'memo_images/a.jpg',
        isImportant: false,
        sortOrder: 0,
        deletedAt: null,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        isDirty: true,
      );
      final json = noteMemoToImportJson(memo);
      expect(json['imageUrl'], isNull);
    });
  });

  group('tagMapToImportJson', () {
    test('localUserBookId/localTagId로 옮긴다', () {
      final mapping = TagMapping(
        id: -3,
        serverId: null,
        userBookId: -1,
        tagId: -2,
        deletedAt: null,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        isDirty: true,
      );
      final json = tagMapToImportJson(mapping);
      expect(json, {'localId': -3, 'localUserBookId': -1, 'localTagId': -2});
    });
  });

  group('buildRecordImportChunks', () {
    Map<String, dynamic> item(int id) => {'localId': id};

    test('한 카테고리 안에서 maxChunkItemCount를 넘으면 나눈다', () {
      final books = List.generate(5, item);
      final chunks = buildRecordImportChunks(
        books: books,
        tags: const [],
        notes: const [],
        noteMemos: const [],
        reflections: const [],
        tagMaps: const [],
        maxChunkItemCount: 2,
      );
      expect(chunks.length, 3);
      expect(chunks[0].books.length, 2);
      expect(chunks[1].books.length, 2);
      expect(chunks[2].books.length, 1);
    });

    test('여러 카테고리를 한도 안에서 한 청크에 합친다', () {
      final chunks = buildRecordImportChunks(
        books: [item(1), item(2)],
        tags: [item(1)],
        notes: const [],
        noteMemos: const [],
        reflections: const [],
        tagMaps: const [],
        maxChunkItemCount: 5,
      );
      expect(chunks.length, 1);
      expect(chunks.single.books.length, 2);
      expect(chunks.single.tags.length, 1);
    });

    test('books → tags → notes → noteMemos → reflections → tagMaps 순서를 유지한다', () {
      final chunks = buildRecordImportChunks(
        books: [item(1)],
        tags: [item(2)],
        notes: [item(3)],
        noteMemos: [item(4)],
        reflections: [item(5)],
        tagMaps: [item(6)],
        maxChunkItemCount: 2,
      );
      // 카테고리 경계에서 나뉘어도(2개씩) 순서상 book이 항상 tag보다 앞 청크
      // 또는 같은 청크의 앞자리에 온다 — 부모가 항상 자식보다 먼저(또는 같은
      // 청크에서 앞서) 전송돼야 한다는 문서 제약을 그대로 반영한 것이다.
      final flattened = chunks.expand((c) => [...c.books, ...c.tags, ...c.notes, ...c.noteMemos, ...c.reflections, ...c.tagMaps]).toList();
      expect(flattened.map((e) => e['localId']), [1, 2, 3, 4, 5, 6]);
    });

    test('모두 비어 있으면 청크가 없다', () {
      final chunks = buildRecordImportChunks(
        books: const [],
        tags: const [],
        notes: const [],
        noteMemos: const [],
        reflections: const [],
        tagMaps: const [],
        maxChunkItemCount: 500,
      );
      expect(chunks, isEmpty);
    });
  });
}
