import 'dart:io';

import 'package:bbbook/features/book_note/data/book_note_dao.dart';
import 'package:bbbook/features/book_note/models/book_note.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/record_sync/models/record_sync_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// AI 메모 생성이 서버 응답을 로컬에 반영하는 [BookNoteDao.upsertServerCreatedMemos]
/// 테스트. 서버가 이미 저장을 끝낸 결과를 그대로 심으므로, 이 메모들은
/// `is_dirty=0`으로 들어가야 하고(다시 push되면 안 된다) 기존 dirty 로컬
/// 편집을 덮어써서도 안 된다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dao = BookNoteDao();
  final now = DateTime.utc(2026, 9, 17);

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final databaseDirectory = await Directory.systemTemp.createTemp(
      'bookshelf_test',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    final databasePath = path.join(databaseDirectory.path, 'bookshelf.db');
    await databaseFactory.deleteDatabase(databasePath);
    await BookshelfDatabase.instance();
  });

  setUp(() async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await txn.delete('book_note_memo');
      await txn.delete('book_note');
      await txn.delete('sync_meta');
    });
  });

  ServerBookNoteMemo aiMemo({
    required int id,
    required int noteId,
    int sortOrder = 0,
  }) {
    return ServerBookNoteMemo(
      id: id,
      noteId: noteId,
      memoType: 'SUMMARY',
      startPage: null,
      endPage: null,
      content: 'AI 생성 메모 $id',
      imageUrl: null,
      isImportant: false,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('AI로 생성된 메모는 이미 동기화된(is_dirty=0) 상태로 삽입된다', () async {
    final note = await dao.createNote(
      ownerUserId: 7,
      userBookId: 20,
      title: '기존 노트',
    );
    await dao.confirmNoteCreated(
      localId: note.id,
      serverId: 900,
      capturedUpdatedAt: note.updatedAt,
    );

    await dao.upsertServerCreatedMemos(
      localNoteId: note.id,
      memos: [
        aiMemo(id: 1001, noteId: 900, sortOrder: 0),
        aiMemo(id: 1002, noteId: 900, sortOrder: 1),
      ],
    );

    final detail = await dao.findDetail(
      ownerUserId: 7,
      userBookId: 20,
      noteId: note.id,
    );
    expect(detail!.memos, hasLength(2));
    for (final memo in detail.memos) {
      expect(memo.isDirty, isFalse);
      expect(memo.serverId, isNotNull);
    }
    // is_dirty=0으로 들어갔으므로 다음 push 대상 목록에도 잡히지 않는다.
    expect(await dao.getNoteIdsWithDirtyMemos(), isEmpty);
  });

  test('아직 push되지 않은 dirty 메모가 있는 노트에 AI 메모를 추가해도 dirty 메모는 보존된다', () async {
    final note = await dao.createNote(
      ownerUserId: 7,
      userBookId: 20,
      title: '기존 노트',
    );
    await dao.confirmNoteCreated(
      localId: note.id,
      serverId: 900,
      capturedUpdatedAt: note.updatedAt,
    );
    final dirtyMemo = await dao.createNoteMemo(
      ownerUserId: 7,
      userBookId: 20,
      noteId: note.id,
      draft: const BookNoteMemoDraft(
        type: BookNoteMemoType.thought,
        content: '아직 서버에 못 보낸 메모',
      ),
      localImagePath: null,
    );

    await dao.upsertServerCreatedMemos(
      localNoteId: note.id,
      memos: [aiMemo(id: 2001, noteId: 900, sortOrder: 1)],
    );

    final detail = await dao.findDetail(
      ownerUserId: 7,
      userBookId: 20,
      noteId: note.id,
    );
    expect(detail!.memos, hasLength(2));
    final stillDirty = detail.memos.singleWhere((m) => m.id == dirtyMemo.id);
    expect(stillDirty.isDirty, isTrue);
    expect(stillDirty.content, '아직 서버에 못 보낸 메모');
  });

  test('빈 목록을 넘기면 아무 것도 하지 않는다', () async {
    final note = await dao.createNote(
      ownerUserId: 7,
      userBookId: 20,
      title: '기존 노트',
    );
    await dao.upsertServerCreatedMemos(localNoteId: note.id, memos: const []);

    final detail = await dao.findDetail(
      ownerUserId: 7,
      userBookId: 20,
      noteId: note.id,
    );
    expect(detail!.memos, isEmpty);
  });
}
