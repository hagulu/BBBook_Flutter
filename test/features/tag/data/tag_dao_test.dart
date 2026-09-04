import 'dart:io';

import 'package:bbbook/features/bookshelf/data/bookshelf_dao.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/bookshelf/models/user_book_create_result.dart';
import 'package:bbbook/features/record_sync/models/record_sync_payload.dart';
import 'package:bbbook/features/tag/data/tag_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// [TagDao]의 로컬 우선 추가/삭제, push 확정(같은 이름 태그 병합 포함),
/// 전체/증분 동기화 반영 로직 테스트.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tagDao = TagDao();
  const bookshelfDao = BookshelfDao();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 테스트 파일은 병렬 실행되므로 파일마다 별도 DB 경로를 쓴다(같은
    // `bookshelf.db`를 공유하면 서로의 setUp이 남의 데이터를 지운다).
    final databaseDirectory = await Directory.systemTemp.createTemp(
      'bookshelf_tag_test',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    final databasePath = path.join(databaseDirectory.path, 'bookshelf.db');
    await databaseFactory.deleteDatabase(databasePath);
    await BookshelfDatabase.instance();
  });

  setUp(() async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await txn.delete('user_book_tag_map');
      await txn.delete('tag');
      await txn.delete('user_book');
      await txn.delete('sync_meta');
    });
  });

  Future<int> createSyncedBook({
    required String clientRequestId,
    required String isbn13,
    required int serverUserBookId,
  }) async {
    final now = DateTime.utc(2026, 9, 1);
    final local = await bookshelfDao.insertLocalCreate(
      BookItem(
        userBookId: 0,
        clientRequestId: clientRequestId,
        isbn13: isbn13,
        title: '태그 테스트 책',
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

  test('태그 추가는 로컬에 즉시 dirty 매핑으로 반영되고, 같은 책에 같은 태그를 다시 추가해도 중복되지 않는다', () async {
    final userBookId = await createSyncedBook(
      clientRequestId: '20000000-0000-4000-8000-000000000001',
      isbn13: '9780000000101',
      serverUserBookId: 601,
    );

    final firstId = await tagDao.addTagLocal(userBookId: userBookId, name: '명작');
    final secondId = await tagDao.addTagLocal(
      userBookId: userBookId,
      name: '명작',
    );
    expect(secondId, firstId, reason: '같은 책에 같은 이름 태그를 다시 추가하면 no-op');

    final mapping = await tagDao.getMappingByLocalId(firstId);
    expect(mapping, isNotNull);
    expect(mapping!.isDirty, isTrue);
    expect(mapping.serverId, isNull);
    expect(mapping.deletedAt, isNull);

    final tag = await tagDao.getTagByLocalId(mapping.tagId);
    expect(tag, isNotNull);
    expect(tag!.name, '명작');
    expect(tag.serverId, isNull, reason: '서버 push 전에는 태그도 서버 ID가 없다');
  });

  test('한 번도 push되지 않은 매핑을 삭제하면 로컬 dirty 삭제로 표시된다', () async {
    final userBookId = await createSyncedBook(
      clientRequestId: '20000000-0000-4000-8000-000000000002',
      isbn13: '9780000000102',
      serverUserBookId: 602,
    );
    final mappingId = await tagDao.addTagLocal(
      userBookId: userBookId,
      name: '감동',
    );

    final removedId = await tagDao.removeTagLocal(
      userBookId: userBookId,
      tagLocalId: (await tagDao.getMappingByLocalId(mappingId))!.tagId,
    );
    expect(removedId, mappingId);

    final mapping = await tagDao.getMappingByLocalId(mappingId);
    expect(mapping, isNotNull);
    expect(mapping!.isDirty, isTrue);
    expect(mapping.deletedAt, isNotNull);
  });

  test('활성 매핑이 없는 태그를 삭제하면 아무 것도 하지 않는다', () async {
    final userBookId = await createSyncedBook(
      clientRequestId: '20000000-0000-4000-8000-000000000003',
      isbn13: '9780000000103',
      serverUserBookId: 603,
    );
    final removedId = await tagDao.removeTagLocal(
      userBookId: userBookId,
      tagLocalId: 999999,
    );
    expect(removedId, isNull);
  });

  test('매핑 생성 push 확정 후 dirty가 풀리고 태그에 서버 ID가 채워진다', () async {
    final userBookId = await createSyncedBook(
      clientRequestId: '20000000-0000-4000-8000-000000000004',
      isbn13: '9780000000104',
      serverUserBookId: 604,
    );
    final mappingId = await tagDao.addTagLocal(
      userBookId: userBookId,
      name: '고전',
    );
    final beforePush = (await tagDao.getMappingByLocalId(mappingId))!;
    final pendingTagLocalId = beforePush.tagId;

    await tagDao.confirmMappingCreated(
      mappingLocalId: mappingId,
      capturedUpdatedAt: beforePush.updatedAt,
      pendingTagLocalId: pendingTagLocalId,
      serverTagId: 9001,
      serverTagName: '고전',
    );

    final mapping = await tagDao.getMappingByLocalId(mappingId);
    expect(mapping!.isDirty, isFalse);

    final tag = await tagDao.getTagByLocalId(mapping.tagId);
    expect(tag!.serverId, 9001);
    expect(tag.name, '고전');
  });

  test('push 확정 중 사용자가 이미 삭제했으면 dirty를 유지해 삭제 push를 이어간다', () async {
    final userBookId = await createSyncedBook(
      clientRequestId: '20000000-0000-4000-8000-000000000005',
      isbn13: '9780000000105',
      serverUserBookId: 605,
    );
    final mappingId = await tagDao.addTagLocal(
      userBookId: userBookId,
      name: '몰입',
    );
    final beforePush = (await tagDao.getMappingByLocalId(mappingId))!;
    final pendingTagLocalId = beforePush.tagId;

    // 서버 요청이 오가는 동안(콜백 이전 시점의 updatedAt을 캡처한 상태로)
    // 사용자가 이미 이 태그를 지웠다고 가정한다.
    await tagDao.removeTagLocal(userBookId: userBookId, tagLocalId: pendingTagLocalId);

    await tagDao.confirmMappingCreated(
      mappingLocalId: mappingId,
      capturedUpdatedAt: beforePush.updatedAt,
      pendingTagLocalId: pendingTagLocalId,
      serverTagId: 9002,
      serverTagName: '몰입',
    );

    final mapping = await tagDao.getMappingByLocalId(mappingId);
    expect(mapping!.isDirty, isTrue, reason: '삭제 push가 아직 남아있다');
    expect(mapping.deletedAt, isNotNull);
  });

  test('오프라인에서 두 책에 같은 이름 태그를 추가하면 하나의 push 확정으로 둘 다 서버 ID를 얻는다', () async {
    final bookA = await createSyncedBook(
      clientRequestId: '20000000-0000-4000-8000-000000000006',
      isbn13: '9780000000106',
      serverUserBookId: 606,
    );
    final bookB = await createSyncedBook(
      clientRequestId: '20000000-0000-4000-8000-000000000007',
      isbn13: '9780000000107',
      serverUserBookId: 607,
    );

    // 오프라인에서 두 책에 같은 이름의(아직 서버에 없는) 태그를 추가한다 —
    // 로컬에서는 addTagLocal의 이름 기준 dedup으로 같은 tag_id를 공유한다.
    final mappingA = await tagDao.addTagLocal(userBookId: bookA, name: '병렬');
    final mappingB = await tagDao.addTagLocal(userBookId: bookB, name: '병렬');
    final sharedPendingTagId = (await tagDao.getMappingByLocalId(mappingA))!.tagId;
    expect((await tagDao.getMappingByLocalId(mappingB))!.tagId, sharedPendingTagId);

    // mappingA의 push가 먼저 성공해 태그가 병합/확정된다.
    final beforePushA = (await tagDao.getMappingByLocalId(mappingA))!;
    await tagDao.confirmMappingCreated(
      mappingLocalId: mappingA,
      capturedUpdatedAt: beforePushA.updatedAt,
      pendingTagLocalId: sharedPendingTagId,
      serverTagId: 9101,
      serverTagName: '병렬',
    );

    // mappingB는 아직 이전 로컬 tag_id를 들고 있었지만, mappingA의 확정이
    // 그 태그 행을 서버 ID로 갈아 끼우며 mappingB의 tag_id도 함께
    // repoint했어야 한다.
    final mappingBAfter = await tagDao.getMappingByLocalId(mappingB);
    expect(mappingBAfter, isNotNull);
    final tagForB = await tagDao.getTagByLocalId(mappingBAfter!.tagId);
    expect(tagForB!.serverId, 9101);
    expect(tagForB.name, '병렬');

    // 이전의 임시(서버 ID 없는) 태그 행은 더는 아무 매핑도 참조하지 않으므로
    // 정리됐어야 한다.
    if (sharedPendingTagId != tagForB.id) {
      expect(await tagDao.getTagByLocalId(sharedPendingTagId), isNull);
    }
  });

  test('같은 이름 태그 충돌: 로컬에 서버 ID가 확정된 별개의 태그 행이 이미 있으면 그 행으로 병합한다', () async {
    final userBookId = await createSyncedBook(
      clientRequestId: '20000000-0000-4000-8000-00000000000a',
      isbn13: '9780000000110',
      serverUserBookId: 610,
    );
    final mappingId = await tagDao.addTagLocal(userBookId: userBookId, name: '겨울');
    final beforePush = (await tagDao.getMappingByLocalId(mappingId))!;
    final pendingTagLocalId = beforePush.tagId;

    // 정상 경로(addTagLocal/applyTagChanges)는 항상 이름으로 먼저 찾기 때문에
    // 같은 이름의 로컬 태그 행이 두 개로 쪼개질 수 없다 — 이 테스트는 그런
    // 비정상 상태(예: 과거 버전 데이터, 수동 복구)에서도 confirm이 안전하게
    // 병합하는지 직접 별도의 서버-확정 태그 행을 만들어 검증한다.
    final db = await BookshelfDatabase.instance();
    final now = DateTime.utc(2026, 9, 1).toIso8601String();
    await db.insert('tag', {
      'id': 9601,
      'server_id': 9601,
      'name': '겨울',
      'deleted_at': null,
      'created_at': now,
      'updated_at': now,
    });

    // 그 뒤 우리 push의 응답이 도착해 confirm이 호출된다 — 같은 serverTagId를
    // 가리키므로 방금 만든 행으로 병합돼야 한다.
    await tagDao.confirmMappingCreated(
      mappingLocalId: mappingId,
      capturedUpdatedAt: beforePush.updatedAt,
      pendingTagLocalId: pendingTagLocalId,
      serverTagId: 9601,
      serverTagName: '겨울',
    );

    final mapping = await tagDao.getMappingByLocalId(mappingId);
    expect(mapping!.tagId, 9601);
    expect(mapping.isDirty, isFalse);
    // 임시로 만들었던 로컬 전용 태그 행은 더는 아무도 참조하지 않으므로 정리된다.
    expect(await tagDao.getTagByLocalId(pendingTagLocalId), isNull);
  });

  test('전체 동기화는 태그/매핑을 반영하고 서버에서 사라진 항목은 삭제하며, dirty 매핑은 보호한다', () async {
    final now = DateTime.utc(2026, 9, 1);
    final keptBookLocalId = await createSyncedBook(
      clientRequestId: '20000000-0000-4000-8000-000000000008',
      isbn13: '9780000000108',
      serverUserBookId: 608,
    );

    // 서버에만 있던 태그/매핑을 최초 전체 동기화로 반영.
    await tagDao.reconcileFullTags(
      activeServerUserBookIds: [608],
      tags: [
        ServerTag(id: 9201, name: '여행', createdAt: now, updatedAt: now),
        ServerTag(id: 9202, name: '요리', createdAt: now, updatedAt: now),
      ],
      tagMaps: [
        ServerTagMap(id: 8301, userBookId: 608, tagId: 9201, createdAt: now, updatedAt: now),
        ServerTagMap(id: 8302, userBookId: 608, tagId: 9202, createdAt: now, updatedAt: now),
      ],
      requestedAt: now,
    );

    var mappedTagNames = await _activeTagNamesForBook(tagDao, keptBookLocalId);
    expect(mappedTagNames, containsAll(['여행', '요리']));

    // 이 사이 오프라인 dirty 편집(태그 추가)이 하나 생겼다고 가정한다.
    final dirtyMappingId = await tagDao.addTagLocal(
      userBookId: keptBookLocalId,
      name: '음악',
    );

    // 다음 전체 동기화 시점에는 서버에서 '요리' 매핑이 사라졌다(태그 자체도
    // 다른 매핑이 없으면 함께 사라진다).
    final later = now.add(const Duration(minutes: 5));
    await tagDao.reconcileFullTags(
      activeServerUserBookIds: [608],
      tags: [ServerTag(id: 9201, name: '여행', createdAt: now, updatedAt: later)],
      tagMaps: [
        ServerTagMap(id: 8301, userBookId: 608, tagId: 9201, createdAt: now, updatedAt: later),
      ],
      requestedAt: later,
    );

    mappedTagNames = await _activeTagNamesForBook(tagDao, keptBookLocalId);
    expect(mappedTagNames, contains('여행'));
    expect(mappedTagNames, isNot(contains('요리')), reason: '서버에서 사라진 매핑은 정리된다');

    // dirty 매핑(아직 push 못한 로컬 편집)은 전체 동기화가 건드리지 않는다.
    final dirtyMapping = await tagDao.getMappingByLocalId(dirtyMappingId);
    expect(dirtyMapping, isNotNull);
    expect(dirtyMapping!.isDirty, isTrue);

    final lastSynced = await tagDao.getLastSyncedAtTag();
    expect(lastSynced, later);
  });

  test('증분 동기화는 upsert/delete를 반영하고, orphan 매핑이 있으면 기준값을 지운다', () async {
    final now = DateTime.utc(2026, 9, 1);
    final bookLocalId = await createSyncedBook(
      clientRequestId: '20000000-0000-4000-8000-000000000009',
      isbn13: '9780000000109',
      serverUserBookId: 609,
    );

    await tagDao.reconcileFullTags(
      activeServerUserBookIds: [609],
      tags: const [],
      tagMaps: const [],
      requestedAt: now,
    );

    final syncedAt = now.add(const Duration(minutes: 10));
    await tagDao.applyTagChanges(
      upsertedTags: [
        ServerTag(id: 9301, name: '판타지', createdAt: now, updatedAt: syncedAt),
      ],
      deletedTagIds: const [],
      upsertedTagMaps: [
        ServerTagMap(
          id: 8401,
          userBookId: 609,
          tagId: 9301,
          createdAt: now,
          updatedAt: syncedAt,
        ),
      ],
      deletedTagMapIds: const [],
      syncedAt: syncedAt,
    );

    var tagNames = await _activeTagNamesForBook(tagDao, bookLocalId);
    expect(tagNames, contains('판타지'));
    expect(await tagDao.getLastSyncedAtTag(), syncedAt);

    // 이어서 이 매핑이 삭제되고 태그도 함께 삭제됐다는 증분 응답.
    final syncedAt2 = syncedAt.add(const Duration(minutes: 10));
    await tagDao.applyTagChanges(
      upsertedTags: const [],
      deletedTagIds: [9301],
      upsertedTagMaps: const [],
      deletedTagMapIds: [8401],
      syncedAt: syncedAt2,
    );

    tagNames = await _activeTagNamesForBook(tagDao, bookLocalId);
    expect(tagNames, isEmpty);
    expect(await tagDao.getLastSyncedAtTag(), syncedAt2);

    // orphan: 로컬에 없는 책을 가리키는 매핑이 오면 기준값을 지워 다음
    // sync가 전체 동기화로 대체되게 한다.
    final syncedAt3 = syncedAt2.add(const Duration(minutes: 10));
    await tagDao.applyTagChanges(
      upsertedTags: [
        ServerTag(id: 9401, name: '미스터리', createdAt: now, updatedAt: syncedAt3),
      ],
      deletedTagIds: const [],
      upsertedTagMaps: [
        ServerTagMap(
          id: 8501,
          userBookId: 999999,
          tagId: 9401,
          createdAt: now,
          updatedAt: syncedAt3,
        ),
      ],
      deletedTagMapIds: const [],
      syncedAt: syncedAt3,
    );
    expect(
      await tagDao.getLastSyncedAtTag(),
      isNull,
      reason: 'orphan 매핑이 있으면 다음 sync가 전체 동기화로 대체되도록 기준값을 지운다',
    );
  });

  test('전체 동기화 중 orphan 매핑이 있으면 last_synced_at_tag를 저장하지 않는다', () async {
    final now = DateTime.utc(2026, 9, 1);
    final knownBookId = await createSyncedBook(
      clientRequestId: '20000000-0000-4000-8000-00000000000b',
      isbn13: '9780000000111',
      serverUserBookId: 611,
    );

    // 응답의 books에는 611만 있지만, tagMaps에는 로컬에 아직 없는 책(612)을
    // 가리키는 매핑도 함께 온다 — 병렬로 실행 중인 책장 동기화가 아직 그
    // 책을 로컬에 반영하지 못한 경우를 흉내낸다.
    await tagDao.reconcileFullTags(
      activeServerUserBookIds: [611, 612],
      tags: [
        ServerTag(id: 9701, name: '알려진 책', createdAt: now, updatedAt: now),
        ServerTag(id: 9702, name: '아직 없는 책', createdAt: now, updatedAt: now),
      ],
      tagMaps: [
        ServerTagMap(id: 8601, userBookId: 611, tagId: 9701, createdAt: now, updatedAt: now),
        ServerTagMap(id: 8602, userBookId: 612, tagId: 9702, createdAt: now, updatedAt: now),
      ],
      requestedAt: now,
    );

    expect(
      await tagDao.getLastSyncedAtTag(),
      isNull,
      reason: '전체 동기화라도 orphan이 있으면 기준값을 남기지 않아야 다음 호출이 다시 전체 동기화를 시도한다',
    );
    // 해석 가능했던 매핑(611)은 정상 반영된다 — orphan 하나 때문에 나머지가
    // 통째로 버려지지 않는다.
    expect(await _activeTagNamesForBook(tagDao, knownBookId), contains('알려진 책'));
  });
}

Future<List<String>> _activeTagNamesForBook(TagDao dao, int userBookLocalId) async {
  final db = await BookshelfDatabase.instance();
  final rows = await db.rawQuery(
    '''
    SELECT t.name AS name
    FROM user_book_tag_map m
    JOIN tag t ON t.id = m.tag_id
    WHERE m.user_book_id = ? AND m.deleted_at IS NULL AND t.deleted_at IS NULL
    ''',
    [userBookLocalId],
  );
  return rows.map((r) => r['name'] as String).toList(growable: false);
}
