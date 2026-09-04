import 'dart:io';

import 'package:bbbook/features/book_note/data/book_note_dao.dart';
import 'package:bbbook/features/book_note/models/book_note.dart';
import 'package:bbbook/features/book_reflection/data/book_reflection_dao.dart';
import 'package:bbbook/features/book_reflection/models/book_reflection.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_dao.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/bookshelf/models/user_book_create_result.dart';
import 'package:bbbook/features/tag/data/tag_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 책 삭제가 하위 기록까지 함께 정리하는지 검증한다.
///
/// `book_note`/`book_reflection`은 `user_book` 외래 키가 없어 자동 CASCADE가
/// 없다. 남겨 두면 로컬 신규 책 ID(`MIN(user_book_id) - 1`)가 재사용될 때
/// 남은 노트·독후감이 엉뚱한 새 책에 붙는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookshelfDao = BookshelfDao();
  const noteDao = BookNoteDao();
  const reflectionDao = BookReflectionDao();
  const tagDao = TagDao();
  final now = DateTime.utc(2026, 8, 24);

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
      await txn.delete('reflection_image_local');
      await txn.delete('book_reflection');
      await txn.delete('user_book_tag_map');
      await txn.delete('tag');
      await txn.delete('user_book');
      await txn.delete('sync_meta');
    });
  });

  Future<BookItem> createLocalBook(String title) {
    return bookshelfDao.insertLocalCreate(
      BookItem(
        userBookId: 0,
        clientRequestId: 'req-$title',
        title: title,
        status: BookStatus.reading,
        currentPage: 0,
        isMasterpiece: false,
        rereadCount: 0,
        tags: const [],
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> addRecords(int userBookId) async {
    final note = await noteDao.createNote(
      ownerUserId: 7,
      userBookId: userBookId,
      title: '노트',
    );
    await noteDao.createNoteMemo(
      ownerUserId: 7,
      userBookId: userBookId,
      noteId: note.id,
      draft: const BookNoteMemoDraft(
        type: BookNoteMemoType.photo,
        imageChange: MemoImageChange.replaced,
      ),
      localImagePath: 'memo_images/local_$userBookId.jpg',
    );
    final reflection = await reflectionDao.createLocal(
      ownerUserId: 7,
      userBookId: userBookId,
      draft: const BookReflectionDraft(
        title: '독후감',
        contentJson: {
          'ops': [
            {'insert': '본문\n'},
          ],
        },
        contentText: '본문',
        isPublic: false,
      ),
    );
    await reflectionDao.replaceLocalImages(
      reflectionId: reflection.id,
      mappings: {
        'https://cdn.example.com/r/$userBookId.jpg':
            'reflection_images/remote_$userBookId.jpg',
      },
    );
  }

  test('책을 지우면 노트·메모·독후감·이미지 매칭도 함께 사라진다', () async {
    final book = await createLocalBook('지울 책');
    final other = await createLocalBook('남을 책');
    await addRecords(book.userBookId);
    await addRecords(other.userBookId);

    await bookshelfDao.deleteOne(book.userBookId);

    expect(
      await noteDao.findByUserBook(ownerUserId: 7, userBookId: book.userBookId),
      isEmpty,
    );
    expect(
      await reflectionDao.findByUserBook(
        ownerUserId: 7,
        userBookId: book.userBookId,
      ),
      isEmpty,
    );
    // 남은 책의 기록은 그대로다.
    expect(
      await noteDao.findByUserBook(
        ownerUserId: 7,
        userBookId: other.userBookId,
      ),
      hasLength(1),
    );
    // 메모 사진·독후감 이미지 매칭도 지운 책 몫만 사라진다.
    expect(await noteDao.getAllLocalImagePaths(), [
      'memo_images/local_${other.userBookId}.jpg',
    ]);
    expect(
      (await reflectionDao.getAllLocalImages()).map((l) => l.localImagePath),
      ['reflection_images/remote_${other.userBookId}.jpg'],
    );
  });

  test('삭제 전에 정리할 로컬 이미지 경로를 모을 수 있다', () async {
    final book = await createLocalBook('표지 있는 책');
    await addRecords(book.userBookId);

    final images = await bookshelfDao.findLocalImagePathsForBook(
      book.userBookId,
    );

    expect(images.memoImages, ['memo_images/local_${book.userBookId}.jpg']);
    expect(images.reflectionImages, [
      'reflection_images/remote_${book.userBookId}.jpg',
    ]);
  });

  test('지운 책의 로컬 ID가 재사용돼도 이전 기록이 딸려오지 않는다', () async {
    final first = await createLocalBook('첫 책');
    await addRecords(first.userBookId);

    await bookshelfDao.deleteOne(first.userBookId);
    final reused = await createLocalBook('새 책');

    // 로컬 ID는 MIN(user_book_id) - 1이라 방금 지운 값이 다시 발급된다.
    expect(reused.userBookId, first.userBookId);
    expect(
      await noteDao.findByUserBook(
        ownerUserId: 7,
        userBookId: reused.userBookId,
      ),
      isEmpty,
    );
    expect(
      await reflectionDao.findByUserBook(
        ownerUserId: 7,
        userBookId: reused.userBookId,
      ),
      isEmpty,
    );
  });

  Future<int> createSyncedBookWithTag({
    required String clientRequestId,
    required int serverUserBookId,
    required String tagName,
  }) async {
    final local = await bookshelfDao.insertLocalCreate(
      BookItem(
        userBookId: 0,
        clientRequestId: clientRequestId,
        title: '태그 있는 책',
        status: BookStatus.reading,
        currentPage: 0,
        isMasterpiece: false,
        rereadCount: 0,
        tags: const [],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await bookshelfDao.confirmCreate(
      localId: local.userBookId,
      capturedUpdatedAt: local.updatedAt,
      response: UserBookCreateResult(
        userBookId: serverUserBookId,
        bookId: serverUserBookId,
        isbn13: null,
        title: '서버 책',
        author: null,
        publisher: null,
        statsTotalPages: null,
        displayTotalPages: null,
        coverImageUrl: null,
        status: 'READING',
        created: false,
      ),
    );
    await tagDao.addTagLocal(userBookId: local.userBookId, name: tagName);
    return local.userBookId;
  }

  test('다른 기기에서 삭제된 책은 전체 동기화 반영에서도 태그 매핑까지 함께 정리돼, 재사용된 로컬 ID에 이전 태그가 남지 않는다', () async {
    final removedBookId = await createSyncedBookWithTag(
      clientRequestId: 'reconcile-removed',
      serverUserBookId: 9001,
      tagName: '이전 태그',
    );

    // 다른 기기에서 이 책을 삭제한 뒤의 전체 동기화 — 서버 목록에 이 책이
    // 더는 없다.
    await bookshelfDao.reconcile(const [], now.add(const Duration(minutes: 1)));

    final rows = await (await BookshelfDatabase.instance()).query(
      'user_book_tag_map',
      where: 'user_book_id = ?',
      whereArgs: [removedBookId],
    );
    expect(rows, isEmpty, reason: '삭제된 책의 태그 매핑도 함께 정리돼야 한다');

    // 로컬 ID는 MIN(user_book_id) - 1이라 방금 지운 값이 다시 발급된다.
    final reused = await createLocalBook('새로 만든 책');
    expect(reused.userBookId, removedBookId);
    expect(await bookshelfDao.getById(reused.userBookId).then((b) => b!.tags), isEmpty);
  });
}
