import 'dart:io';

import 'package:bbbook/features/book_reflection/data/book_reflection_dao.dart';
import 'package:bbbook/features/book_reflection/models/book_reflection.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_dao.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/bookshelf/models/user_book_create_result.dart';
import 'package:bbbook/features/record_sync/models/record_sync_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// [BookReflectionDao]의 전체/증분 동기화 반영 로직 테스트.
/// [BookNoteDao]와 같은 원칙(서버에 없는 항목 정리, orphan 시 기준값 초기화)이
/// 독후감에도 그대로 적용되는지 확인한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 테스트 파일은 병렬 실행되므로 파일마다 별도 DB 경로를 쓴다(같은
    // `bookshelf.db`를 공유하면 서로의 setUp이 남의 데이터를 지운다).
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
      await txn.delete('book_reflection');
      await txn.delete('book_note_memo');
      await txn.delete('book_note');
      await txn.delete('user_book_tag');
      await txn.delete('user_book');
      await txn.delete('sync_meta');
    });
  });

  Future<int> createSyncedBook({
    required String clientRequestId,
    required String isbn13,
    required int serverUserBookId,
  }) async {
    const bookshelfDao = BookshelfDao();
    final now = DateTime.utc(2026, 8, 20);
    final local = await bookshelfDao.insertLocalCreate(
      BookItem(
        userBookId: 0,
        clientRequestId: clientRequestId,
        isbn13: isbn13,
        title: '독후감 테스트 책',
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
        isbn13: isbn13,
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
    return local.userBookId;
  }

  test('전체 동기화는 독후감을 반영하고 서버에서 사라진 항목은 삭제한다', () async {
    const reflectionDao = BookReflectionDao();
    final now = DateTime.utc(2026, 8, 20);
    final localUserBookId = await createSyncedBook(
      clientRequestId: '10000000-0000-4000-8000-000000000001',
      isbn13: '9780000000001',
      serverUserBookId: 501,
    );

    final reflectionA = ServerBookReflection(
      id: 1001,
      userBookId: 501,
      reflectionType: 'USER_WRITTEN',
      title: '첫 독후감',
      contentJson: const {'type': 'doc', 'content': []},
      contentText: '본문 A',
      isPublic: true,
      isHidden: false,
      createdAt: now,
      updatedAt: now,
    );
    final reflectionB = ServerBookReflection(
      id: 1002,
      userBookId: 501,
      reflectionType: 'USER_WRITTEN',
      title: '둘째 독후감',
      contentJson: null,
      contentText: '본문 B',
      isPublic: false,
      isHidden: false,
      createdAt: now,
      updatedAt: now,
    );

    await reflectionDao.reconcileFullReflection(
      ownerUserId: 3,
      activeUserBookIds: const [501],
      reflections: [reflectionA, reflectionB],
      requestedAt: now,
    );

    final list = await reflectionDao.findByUserBook(
      ownerUserId: 3,
      userBookId: localUserBookId,
    );
    expect(list.map((r) => r.id).toSet(), {1001, 1002});

    final detail = await reflectionDao.findDetail(
      ownerUserId: 3,
      userBookId: localUserBookId,
      reflectionId: 1001,
    );
    expect(detail?.title, '첫 독후감');
    expect(detail?.contentJson, {'type': 'doc', 'content': []});
    expect(detail?.contentText, '본문 A');
    expect(await reflectionDao.getLastSyncedAtReflection(), now);

    // 두 번째 전체 동기화: reflectionB가 서버 응답에서 사라짐 → 로컬에서도
    // 삭제되어야 한다(책은 여전히 activeUserBookIds에 있으므로).
    final later = now.add(const Duration(minutes: 1));
    await reflectionDao.reconcileFullReflection(
      ownerUserId: 3,
      activeUserBookIds: const [501],
      reflections: [reflectionA],
      requestedAt: later,
    );
    final afterPrune = await reflectionDao.findByUserBook(
      ownerUserId: 3,
      userBookId: localUserBookId,
    );
    expect(afterPrune.map((r) => r.id), [1001]);
    expect(await reflectionDao.getLastSyncedAtReflection(), later);
  });

  test('신규 독후감은 로컬 우선 저장 후 서버 ID를 확정해도 로컬 PK를 유지한다', () async {
    const reflectionDao = BookReflectionDao();
    final localUserBookId = await createSyncedBook(
      clientRequestId: '10000000-0000-4000-8000-000000000004',
      isbn13: '9780000000004',
      serverUserBookId: 504,
    );
    const draft = BookReflectionDraft(
      title: '로컬 독후감',
      contentJson: {
        'ops': [
          {'insert': '로컬 본문\n'},
        ],
      },
      contentText: '로컬 본문',
      isPublic: false,
    );

    final local = await reflectionDao.createLocal(
      ownerUserId: 9,
      userBookId: localUserBookId,
      draft: draft,
    );

    expect(local.id, lessThan(0));
    expect(local.serverId, isNull);
    expect(local.clientRequestId, isNotEmpty);
    expect(local.isDirty, isTrue);

    final serverResult = BookReflectionServerResult(
      id: 4001,
      userBookId: 504,
      reflectionType: 'USER_WRITTEN',
      title: draft.title,
      contentJson: draft.contentJson,
      contentText: draft.contentText,
      isPublic: draft.isPublic,
      createdAt: local.createdAt.add(const Duration(seconds: 1)),
      updatedAt: local.updatedAt.add(const Duration(seconds: 1)),
    );
    await reflectionDao.confirmPush(
      localId: local.id,
      capturedUpdatedAt: local.updatedAt,
      result: serverResult,
    );

    final confirmed = await reflectionDao.findDetail(
      ownerUserId: 9,
      userBookId: localUserBookId,
      reflectionId: local.id,
    );
    expect(confirmed?.id, local.id);
    expect(confirmed?.serverId, 4001);
    expect(confirmed?.isDirty, isFalse);

    final visibilityChanged = await reflectionDao.updateVisibilityLocal(
      ownerUserId: 9,
      userBookId: localUserBookId,
      reflectionId: local.id,
      isPublic: true,
    );
    expect(visibilityChanged.isPublic, isTrue);
    expect(visibilityChanged.isDirty, isFalse);

    final edited = await reflectionDao.updateLocal(
      ownerUserId: 9,
      userBookId: localUserBookId,
      reflectionId: local.id,
      draft: const BookReflectionDraft(
        title: '수정된 독후감',
        contentJson: {
          'ops': [
            {'insert': '수정 본문\n'},
          ],
        },
        contentText: '수정 본문',
        isPublic: true,
      ),
    );
    expect(edited.serverId, 4001);
    expect(edited.isDirty, isTrue);
    expect(edited.contentText, '수정 본문');

    final deleted = await reflectionDao.markDeletedLocal(
      ownerUserId: 9,
      userBookId: localUserBookId,
      reflectionId: local.id,
    );
    expect(deleted.deletedAt, isNotNull);
    expect(deleted.isDirty, isTrue);
    expect(
      await reflectionDao.findDetail(
        ownerUserId: 9,
        userBookId: localUserBookId,
        reflectionId: local.id,
      ),
      isNull,
    );
    expect((await reflectionDao.getDirty()).single.id, local.id);

    await reflectionDao.confirmDelete(
      localId: local.id,
      capturedUpdatedAt: deleted.updatedAt,
    );
    expect(await reflectionDao.getByLocalId(local.id), isNull);
  });

  test('증분 동기화는 upsert/삭제를 반영한다', () async {
    const reflectionDao = BookReflectionDao();
    final now = DateTime.utc(2026, 8, 20);
    final localUserBookId = await createSyncedBook(
      clientRequestId: '10000000-0000-4000-8000-000000000002',
      isbn13: '9780000000002',
      serverUserBookId: 502,
    );

    final upserted = ServerBookReflection(
      id: 2001,
      userBookId: 502,
      reflectionType: 'USER_WRITTEN',
      title: '증분 독후감',
      contentJson: null,
      contentText: '증분 본문',
      isPublic: false,
      isHidden: false,
      createdAt: now,
      updatedAt: now,
    );

    await reflectionDao.applyReflectionChanges(
      ownerUserId: 5,
      upsertedReflections: [upserted],
      deletedReflectionIds: const [],
      syncedAt: now,
    );

    final afterUpsert = await reflectionDao.findByUserBook(
      ownerUserId: 5,
      userBookId: localUserBookId,
    );
    expect(afterUpsert.map((r) => r.id), [2001]);
    expect(await reflectionDao.getLastSyncedAtReflection(), now);

    final later = now.add(const Duration(minutes: 5));
    await reflectionDao.applyReflectionChanges(
      ownerUserId: 5,
      upsertedReflections: const [],
      deletedReflectionIds: const [2001],
      syncedAt: later,
    );
    final afterDelete = await reflectionDao.findByUserBook(
      ownerUserId: 5,
      userBookId: localUserBookId,
    );
    expect(afterDelete, isEmpty);
    expect(await reflectionDao.getLastSyncedAtReflection(), later);
  });

  test('부모 책을 로컬에서 찾지 못한 증분 항목(orphan)은 동기화 기준값을 초기화한다', () async {
    const reflectionDao = BookReflectionDao();
    final now = DateTime.utc(2026, 8, 20);

    // 사전 조건: 기준값이 이미 설정돼 있어야 "초기화"를 확인할 수 있다.
    await reflectionDao.applyReflectionChanges(
      ownerUserId: 7,
      upsertedReflections: const [],
      deletedReflectionIds: const [],
      syncedAt: now,
    );
    expect(await reflectionDao.getLastSyncedAtReflection(), now);

    final orphan = ServerBookReflection(
      id: 3001,
      userBookId: 999999, // 로컬에 없는 책
      reflectionType: 'USER_WRITTEN',
      title: '고아 독후감',
      contentJson: null,
      contentText: null,
      isPublic: false,
      isHidden: false,
      createdAt: now,
      updatedAt: now,
    );

    await reflectionDao.applyReflectionChanges(
      ownerUserId: 7,
      upsertedReflections: [orphan],
      deletedReflectionIds: const [],
      syncedAt: now.add(const Duration(minutes: 10)),
    );

    expect(await reflectionDao.getLastSyncedAtReflection(), isNull);
  });
}
