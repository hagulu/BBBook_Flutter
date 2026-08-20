import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../bookshelf/data/bookshelf_database.dart';
import '../../record_sync/models/record_sync_payload.dart';
import '../models/book_memo.dart';

/// 메모/메모 조각 로컬 DB 쿼리/쓰기 전담.
///
/// `book_memo`/`book_memo_item`의 `id`는 로컬 PK로, 오프라인 생성 시
/// [_nextLocalId]가 부여하는 음수 임시값일 수 있다. 서버에 반영된 뒤에는
/// `server_id`에 서버가 내려준 진짜 ID를 채우되 `id`는 절대 바꾸지 않는다
/// (이유는 `BookshelfDatabase._createRecordTables` 참고). `is_dirty = 1`인
/// 행은 [reconcileFullMemo]/[applyMemoChanges](서버 조회 반영) 모두 덮어쓰거나
/// 삭제하지 않는다 — 아직 push되지 못한 로컬 우선 편집을 지키기 위함이다.
class BookMemoDao {
  const BookMemoDao();

  Future<List<BookMemoSummary>> findByUserBook({
    required int ownerUserId,
    required int userBookId,
  }) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.rawQuery(
      '''
      SELECT m.*,
             COUNT(i.id) AS item_count,
             MIN(COALESCE(i.start_page, i.end_page)) AS first_page,
             MAX(COALESCE(i.end_page, i.start_page)) AS last_page
      FROM book_memo m
      LEFT JOIN book_memo_item i
        ON i.memo_id = m.id AND i.deleted_at IS NULL
      WHERE m.owner_user_id = ?
        AND m.user_book_id = ?
        AND m.deleted_at IS NULL
      GROUP BY m.id
      ORDER BY m.updated_at DESC, m.id DESC
      ''',
      [ownerUserId, userBookId],
    );
    return rows
        .map(
          (row) => BookMemoSummary(
            memo: _memoFromRow(row),
            itemCount: (row['item_count'] as int?) ?? 0,
            firstPage: row['first_page'] as int?,
            lastPage: row['last_page'] as int?,
          ),
        )
        .toList(growable: false);
  }

  Future<BookMemoDetail?> findDetail({
    required int ownerUserId,
    required int userBookId,
    required int memoId,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final memoRows = await txn.query(
        'book_memo',
        where:
            'id = ? AND owner_user_id = ? AND user_book_id = ? '
            'AND deleted_at IS NULL',
        whereArgs: [memoId, ownerUserId, userBookId],
        limit: 1,
      );
      if (memoRows.isEmpty) return null;

      final itemRows = await txn.query(
        'book_memo_item',
        where: 'memo_id = ? AND deleted_at IS NULL',
        whereArgs: [memoId],
        orderBy: 'created_at ASC, sort_order ASC, id ASC',
      );
      return BookMemoDetail(
        memo: _memoFromRow(memoRows.single),
        items: itemRows.map(_itemFromRow).toList(growable: false),
      );
    });
  }

  Future<BookMemo> createMemo({
    required int ownerUserId,
    required int userBookId,
    required String? title,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final id = await _nextLocalId(txn, 'book_memo');
      final now = DateTime.now().toUtc().toIso8601String();
      final values = <String, Object?>{
        'id': id,
        'server_id': null,
        'owner_user_id': ownerUserId,
        'user_book_id': userBookId,
        'title': title,
        'deleted_at': null,
        'created_at': now,
        'updated_at': now,
        'is_dirty': 1,
      };
      await txn.insert('book_memo', values);
      return _memoFromRow(values);
    });
  }

  Future<BookMemo> updateTitle({
    required int ownerUserId,
    required int userBookId,
    required int memoId,
    required String? title,
  }) async {
    final db = await BookshelfDatabase.instance();
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await db.update(
      'book_memo',
      {'title': title, 'updated_at': now, 'is_dirty': 1},
      where:
          'id = ? AND owner_user_id = ? AND user_book_id = ? '
          'AND deleted_at IS NULL',
      whereArgs: [memoId, ownerUserId, userBookId],
    );
    if (count != 1) throw StateError('Memo not found');

    final rows = await db.query(
      'book_memo',
      where: 'id = ?',
      whereArgs: [memoId],
      limit: 1,
    );
    return _memoFromRow(rows.single);
  }

  Future<BookMemoItem> createItem({
    required int ownerUserId,
    required int userBookId,
    required int memoId,
    required BookMemoItemDraft draft,
    required String? imageUrl,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      await _requireActiveMemo(
        txn,
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        memoId: memoId,
      );
      final id = await _nextLocalId(txn, 'book_memo_item');
      final orderRows = await txn.rawQuery(
        'SELECT MAX(sort_order) AS max_order FROM book_memo_item '
        'WHERE memo_id = ? AND deleted_at IS NULL',
        [memoId],
      );
      final maxOrder = orderRows.single['max_order'] as int?;
      final now = DateTime.now().toUtc().toIso8601String();
      final values = <String, Object?>{
        'id': id,
        'server_id': null,
        // 네트워크 push가 아니라 로컬 신규 생성 트랜잭션에서 한 번만
        // 발급한다. 이후 재시도는 이 컬럼을 다시 읽어 같은 값을 사용한다.
        'client_request_id': const Uuid().v4(),
        'memo_id': memoId,
        'item_type': draft.type.dbValue,
        'start_page': draft.startPage,
        'end_page': draft.endPage,
        'content': draft.content,
        'image_url': imageUrl,
        'is_important': draft.isImportant ? 1 : 0,
        'sort_order': (maxOrder ?? -1) + 1,
        'deleted_at': null,
        'created_at': now,
        'updated_at': now,
        'is_dirty': 1,
      };
      await txn.insert('book_memo_item', values);
      return _itemFromRow(values);
    });
  }

  Future<BookMemoItem> updateItem({
    required int ownerUserId,
    required int userBookId,
    required int memoId,
    required int itemId,
    required BookMemoItemDraft draft,
    required String? imageUrl,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      await _requireActiveMemo(
        txn,
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        memoId: memoId,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      final count = await txn.update(
        'book_memo_item',
        {
          'item_type': draft.type.dbValue,
          'start_page': draft.startPage,
          'end_page': draft.endPage,
          'content': draft.content,
          'image_url': imageUrl,
          'is_important': draft.isImportant ? 1 : 0,
          'updated_at': now,
          'is_dirty': 1,
        },
        where: 'id = ? AND memo_id = ? AND deleted_at IS NULL',
        whereArgs: [itemId, memoId],
      );
      if (count != 1) throw StateError('Memo item not found');
      final rows = await txn.query(
        'book_memo_item',
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      return _itemFromRow(rows.single);
    });
  }

  Future<DeleteMemoItemResult> deleteItem({
    required int ownerUserId,
    required int userBookId,
    required int memoId,
    required int itemId,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      await _requireActiveMemo(
        txn,
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        memoId: memoId,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      final count = await txn.update(
        'book_memo_item',
        {'deleted_at': now, 'updated_at': now, 'is_dirty': 1},
        where: 'id = ? AND memo_id = ? AND deleted_at IS NULL',
        whereArgs: [itemId, memoId],
      );
      if (count != 1) throw StateError('Memo item not found');

      final remainingRows = await txn.rawQuery(
        'SELECT COUNT(*) AS item_count FROM book_memo_item '
        'WHERE memo_id = ? AND deleted_at IS NULL',
        [memoId],
      );
      final hasRemaining = (remainingRows.single['item_count'] as int) > 0;
      if (!hasRemaining) {
        await txn.update(
          'book_memo',
          {'deleted_at': now, 'updated_at': now, 'is_dirty': 1},
          where: 'id = ?',
          whereArgs: [memoId],
        );
      }
      return DeleteMemoItemResult(memoWasDeleted: !hasRemaining);
    });
  }

  /// 메모 자체를 소프트 삭제한다. 조각은 건드리지 않는다 — 부모 메모가
  /// `deleted_at IS NOT NULL`이 되는 순간 [findByUserBook]/[findDetail]
  /// 모두 이 메모를 더 이상 보여주지 않으므로 화면상으로는 조각까지 함께
  /// 사라진 것과 같고, 실제 서버 반영은 push 시점에 메모 전용 삭제 API
  /// 한 번으로 조각까지 함께 처리된다([BookMemoRepository]의 push 로직
  /// 참고).
  Future<void> deleteMemo({
    required int ownerUserId,
    required int userBookId,
    required int memoId,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await _requireActiveMemo(
        txn,
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        memoId: memoId,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        'book_memo',
        {'deleted_at': now, 'updated_at': now, 'is_dirty': 1},
        where: 'id = ?',
        whereArgs: [memoId],
      );
    });
  }

  /// 메모 삭제 push([BookMemoRepository._pushDeletedMemo])가 정리할 이미지를
  /// 판단하기 위해, 삭제 여부와 상관없이 그 메모에 딸린 조각 전부를 반환한다.
  Future<List<BookMemoItem>> getAllItemsForMemo(int memoLocalId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_memo_item',
      where: 'memo_id = ?',
      whereArgs: [memoLocalId],
    );
    return rows.map(_itemFromRow).toList(growable: false);
  }

  /// 삭제 push가 끝난(또는 애초에 서버에 없던) 메모와 그 조각 전부를
  /// 로컬에서 물리 삭제한다.
  Future<void> purgeMemoAndItems(int memoLocalId) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await txn.delete(
        'book_memo_item',
        where: 'memo_id = ?',
        whereArgs: [memoLocalId],
      );
      await txn.delete('book_memo', where: 'id = ?', whereArgs: [memoLocalId]);
    });
  }

  // ---------------------------------------------------------------------
  // 서버 동기화(dirty push) 전용
  // ---------------------------------------------------------------------

  Future<DateTime?> getLastSyncedAtMemo() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['last_synced_at_memo'],
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['value'] as String);
  }

  /// 제목 편집 등으로 dirty가 된(is_dirty=1) 메모의 로컬 ID 목록.
  Future<List<int>> getDirtyMemoLocalIds() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_memo',
      columns: ['id'],
      where: 'is_dirty = 1',
    );
    return rows.map((r) => r['id'] as int).toList(growable: false);
  }

  /// dirty(is_dirty=1) 조각이 하나라도 있는 메모의 로컬 ID 목록(중복 제거).
  Future<List<int>> getMemoIdsWithDirtyItems() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.rawQuery(
      'SELECT DISTINCT memo_id FROM book_memo_item WHERE is_dirty = 1',
    );
    return rows.map((r) => r['memo_id'] as int).toList(growable: false);
  }

  Future<BookMemo?> getMemoByLocalId(int localId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_memo',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    return rows.isEmpty ? null : _memoFromRow(rows.single);
  }

  /// 특정 메모에 속한 dirty 조각(생성/수정/삭제 대기 중) 전체. 소프트
  /// 삭제된(`deleted_at != null`) 조각도 포함한다 — push 쪽에서 삭제
  /// 요청으로 처리해야 하므로.
  ///
  /// `created_at ASC`로 정렬한다 — `id ASC`를 쓰면 로컬 전용 조각의 음수
  /// ID가 생성 순서와 거꾸로(가장 최근 것이 가장 작은 음수) 정렬돼, 제목
  /// 없는 신규 메모를 만들 때 가장 나중에 추가한 조각이 먼저 push되며 메모를
  /// 만들어버리고, 서버 `sortOrder`("마지막 순서 다음 값")도 로컬 표시
  /// 순서와 반대로 매겨진다.
  Future<List<BookMemoItem>> getDirtyItemsForMemo(int memoLocalId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_memo_item',
      where: 'memo_id = ? AND is_dirty = 1',
      whereArgs: [memoLocalId],
      orderBy: 'created_at ASC, id DESC',
    );
    return rows.map(_itemFromRow).toList(growable: false);
  }

  /// 이미 서버에 존재하던 메모(`server_id != null`)의 제목 push가 성공한 뒤
  /// 호출한다. push 요청을 만들 때 읽은 [capturedUpdatedAt]과 현재 로컬
  /// `updated_at`이 같을 때만(그 사이 새 로컬 편집이 없었을 때만) dirty를
  /// 해제한다 — 네트워크가 오가는 동안 사용자가 제목을 또 수정했다면 그
  /// 편집은 아직 반영되지 않았으므로 dirty를 유지해 다음 push가 최신 내용을
  /// 다시 보내게 한다.
  Future<void> confirmMemoTitlePush({
    required int localId,
    required DateTime capturedUpdatedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'book_memo',
        columns: ['updated_at'],
        where: 'id = ?',
        whereArgs: [localId],
      );
      if (rows.isEmpty) return;
      final current = DateTime.parse(rows.single['updated_at'] as String);
      if (!current.isAtSameMomentAs(capturedUpdatedAt)) return;
      await txn.update(
        'book_memo',
        {'is_dirty': 0},
        where: 'id = ?',
        whereArgs: [localId],
      );
    });
  }

  /// 로컬 전용(`server_id IS NULL`) 메모가 제목 PUT으로 서버에 처음
  /// 생성된 뒤 호출한다. `server_id`는(신원 확정이므로) 항상 채우고, dirty
  /// 해제는 [confirmMemoTitlePush]와 동일하게 그 사이 새 편집이 없었을
  /// 때만 한다.
  Future<void> confirmMemoCreated({
    required int localId,
    required int serverId,
    required DateTime capturedUpdatedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'book_memo',
        columns: ['updated_at'],
        where: 'id = ?',
        whereArgs: [localId],
      );
      if (rows.isEmpty) return;
      final current = DateTime.parse(rows.single['updated_at'] as String);
      final unchanged = current.isAtSameMomentAs(capturedUpdatedAt);
      await txn.update(
        'book_memo',
        {'server_id': serverId, if (unchanged) 'is_dirty': 0},
        where: 'id = ?',
        whereArgs: [localId],
      );
    });
  }

  /// 조각 생성/수정 push가 성공한 뒤 서버 응답으로 확정 반영한다. `server_id`는
  /// 항상 채우고(신원 확정), 필드 값은 push 요청을 만들 때 읽은
  /// [capturedUpdatedAt]과 현재 로컬 `updated_at`이 같을 때만(그 사이 새
  /// 로컬 편집이 없었을 때만) 서버 응답으로 덮어써 dirty를 해제한다 — 그
  /// 렇지 않으면 아직 반영되지 않은 최신 로컬 편집을 이전 push의 응답으로
  /// 되돌리게 된다.
  ///
  /// 반환값은 필드 값까지 실제로 반영됐는지 여부(위 "unchanged" 조건). 호출
  /// 쪽(`BookMemoRepository._confirmItemAndCleanupImage`)이 이 값을 보고
  /// `image_url`이 실제로 새 원격 URL로 바뀌었는지 판단해야, DB가 여전히
  /// 옛 로컬 사진 경로를 참조하는데 그 파일을 지워버리는 사고를 막는다.
  Future<bool> confirmItemSynced({
    required int localId,
    required int serverId,
    required DateTime capturedUpdatedAt,
    required BookMemoItemType itemType,
    required int? startPage,
    required int? endPage,
    required String? content,
    required String? imageUrl,
    required bool isImportant,
    required int sortOrder,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'book_memo_item',
        columns: ['updated_at'],
        where: 'id = ?',
        whereArgs: [localId],
      );
      if (rows.isEmpty) return false;
      final storedUpdatedAt = rows.single['updated_at'] as String?;
      final current = storedUpdatedAt == null
          ? null
          : DateTime.parse(storedUpdatedAt);
      final unchanged =
          current != null && current.isAtSameMomentAs(capturedUpdatedAt);
      if (unchanged) {
        await txn.update(
          'book_memo_item',
          {
            'server_id': serverId,
            'item_type': itemType.dbValue,
            'start_page': startPage,
            'end_page': endPage,
            'content': content,
            'image_url': imageUrl,
            'is_important': isImportant ? 1 : 0,
            'sort_order': sortOrder,
            'is_dirty': 0,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      } else {
        await txn.update(
          'book_memo_item',
          {'server_id': serverId},
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
      return unchanged;
    });
  }

  /// 삭제 push(또는 애초에 서버에 없던 로컬 전용 조각의 정리)가 끝난 조각을
  /// 로컬에서 물리 삭제한다.
  Future<void> purgeItem(int localId) async {
    final db = await BookshelfDatabase.instance();
    await db.delete('book_memo_item', where: 'id = ?', whereArgs: [localId]);
  }

  /// `/api/me/records` 전체 조회 결과로 메모/조각 테이블을 맞춘다: 서버에
  /// 있는 행은 upsert, 서버에 없는(로컬에만 남은) 비-dirty 행은 삭제. dirty
  /// 행(및 dirty 조각이 하나라도 남은 메모)은 건드리지 않는다.
  ///
  /// [activeUserBookIds]는 같은 `/api/me/records` 응답의 `books` 배열이다.
  /// 이 API는 "소프트 삭제된 책장 항목의 데이터는 포함하지 않는다"(api-doc)
  /// — 즉 책이 서재에서 삭제되면 그 책의 메모/조각도 이번 응답의 [memos]/
  /// [items]에서 통째로 빠진다. 이를 "서버에서 삭제됨"으로 오인해 지우면
  /// 아직 서재 삭제 자체는 동기화되지 않은(또는 영구 보관되는) 메모 데이터를
  /// 잃는다. 그래서 "메모/조각이 없다"만으로 삭제하지 않고, 그 메모의
  /// `user_book_id`가 이번 응답에 실제로 존재하는 책일 때만(=책은 그대로
  /// 있는데 메모만 없어졌을 때만) 삭제 대상으로 본다.
  ///
  /// [requestedAt]은 이 전체 동기화 요청을 보내기 *직전* 시각(UTC)이어야
  /// 한다 — 응답을 받은 뒤 시각을 쓰면 그 사이 서버에 반영된 변경이 다음
  /// 증분 동기화의 since보다 앞서게 되어 영구히 누락될 수 있다.
  Future<void> reconcileFullMemo({
    required int ownerUserId,
    required List<int> activeUserBookIds,
    required List<ServerBookMemo> memos,
    required List<ServerBookMemoItem> items,
    required DateTime requestedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final localActiveUserBookIds = await _localUserBookIdsForServerIds(
        txn,
        activeUserBookIds,
      );
      for (final memo in memos) {
        await _upsertServerMemoTxn(txn, ownerUserId, memo);
      }
      for (final item in items) {
        final localMemoId = await _findLocalMemoIdByServerId(txn, item.memoId);
        if (localMemoId == null) {
          // 전체 조회 응답은 memos/items가 FK로 일관되어야 한다
          // (record_sync의 RecordSyncPayload._validateRelationships와 같은
          // 보장) — 그런데도 로컬에서 부모를 못 찾으면 이 조각은 이번
          // 전체 동기화로 복구할 수 없다는 뜻이므로 조용히 버리지 않고
          // 로그만 남긴다.
          developer.log(
            '[메모 전체 동기화] result=SKIP reason=orphan_item '
            'serverItemId=${item.id} serverMemoId=${item.memoId}',
          );
          continue;
        }
        await _upsertServerItemTxn(txn, localMemoId, item);
      }

      // 조각 삭제를 메모 삭제보다 먼저 실행한다. 순서를 반대로 하면(메모
      // 삭제 먼저) 응답에 없는(=서버에서 사라진) 메모가 이 시점에 이미
      // CASCADE로 자기 조각까지 함께 지워버려서, "메모는 그대로인데 조각
      // 하나만 삭제 보관 기간(30일)을 넘겨 deletedItemIds에도 더 이상
      // 안 잡히는" 케이스를 이 아래 조각 삭제 쿼리가 더 이상 볼 수 없게
      // 된다(그때는 이미 그 메모 밑에 남은 조각이 서버 응답과 항상
      // 일치하므로 "없는 조각" 자체가 안 잡힘) — 바로 이 케이스가 전체
      // 동기화가 존재하는 이유이므로 먼저 처리해야 한다.
      final serverItemIds = items.map((i) => i.id).toList(growable: false);
      await _deleteMissingItemsTxn(
        txn,
        ownerUserId,
        localActiveUserBookIds,
        serverItemIds,
      );

      final serverMemoIds = memos.map((m) => m.id).toList(growable: false);
      await _deleteMissingMemosTxn(
        txn,
        ownerUserId,
        localActiveUserBookIds,
        serverMemoIds,
      );

      await txn.insert('sync_meta', {
        'key': 'last_synced_at_memo',
        'value': requestedAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// `/api/me/memos/sync/changes` 증분 동기화 결과를 반영한다. dirty 행은
  /// [reconcileFullMemo]와 동일하게 보호한다. 변경이 없어도 매번
  /// `last_synced_at_memo`를 앞으로 당긴다(다음 요청이 갈수록 넓어지는
  /// 구간을 다시 스캔하지 않도록) — 단, 부모 메모를 로컬에서 찾지 못한
  /// 조각(orphan)이 하나라도 있었으면 그 조각은 이번 반영에서 영구히
  /// 유실되므로 기준값을 앞으로 당기지 않고 아예 지운다. 그러면 다음
  /// [BookMemoRepository.sync] 호출이 `since == null`로 판단해 전체
  /// 동기화(`/api/me/records`)로 대체되어 놓친 조각을 되찾는다 — 같은
  /// since로 증분을 다시 시도해 봤자 서버는 같은(이미 유실 처리된) 응답을
  /// 되풀이할 뿐이라 증분 재시도로는 복구되지 않는다.
  Future<void> applyMemoChanges({
    required int ownerUserId,
    required List<ServerBookMemo> upsertedMemos,
    required List<int> deletedMemoIds,
    required List<ServerBookMemoItem> upsertedItems,
    required List<int> deletedItemIds,
    required DateTime syncedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      for (final memo in upsertedMemos) {
        // 증분 응답에는 owner_user_id가 내려오지 않는다(API가 이미 로그인
        // 사용자 소유 메모만 반환하므로). book_memo.owner_user_id는 서버
        // 응답 필드가 아닌 로컬 계정 격리용 값이라, 신규 삽입 시 호출자가
        // 넘긴 현재 세션 사용자 ID로 채운다.
        await _upsertServerMemoTxn(txn, ownerUserId, memo);
      }
      var hasOrphanItem = false;
      for (final item in upsertedItems) {
        final localMemoId = await _findLocalMemoIdByServerId(txn, item.memoId);
        if (localMemoId == null) {
          hasOrphanItem = true;
          developer.log(
            '[메모 증분 동기화] result=SKIP reason=orphan_item '
            'serverItemId=${item.id} serverMemoId=${item.memoId}',
          );
          continue;
        }
        await _upsertServerItemTxn(txn, localMemoId, item);
      }

      if (deletedMemoIds.isNotEmpty) {
        final placeholders = List.filled(deletedMemoIds.length, '?').join(', ');
        await txn.delete(
          'book_memo',
          where:
              'server_id IN ($placeholders) AND is_dirty = 0 '
              'AND NOT EXISTS (SELECT 1 FROM book_memo_item '
              'WHERE memo_id = book_memo.id AND is_dirty = 1)',
          whereArgs: deletedMemoIds,
        );
      }
      if (deletedItemIds.isNotEmpty) {
        final placeholders = List.filled(deletedItemIds.length, '?').join(', ');
        await txn.delete(
          'book_memo_item',
          where: 'server_id IN ($placeholders) AND is_dirty = 0',
          whereArgs: deletedItemIds,
        );
      }

      if (hasOrphanItem) {
        await txn.delete(
          'sync_meta',
          where: 'key = ?',
          whereArgs: ['last_synced_at_memo'],
        );
      } else {
        await txn.insert('sync_meta', {
          'key': 'last_synced_at_memo',
          'value': syncedAt.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<int> _upsertServerMemoTxn(
    Transaction txn,
    int ownerUserId,
    ServerBookMemo memo,
  ) async {
    final localUserBookId =
        await _findLocalUserBookIdByServerId(txn, memo.userBookId) ??
        memo.userBookId;
    final existing = await txn.query(
      'book_memo',
      columns: ['id', 'is_dirty'],
      where: 'server_id = ?',
      whereArgs: [memo.id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final localId = existing.single['id'] as int;
      final isDirty = existing.single['is_dirty'] == 1;
      if (!isDirty) {
        await txn.update(
          'book_memo',
          {
            'title': memo.title,
            'user_book_id': localUserBookId,
            'deleted_at': null,
            'updated_at': memo.updatedAt.toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
      return localId;
    }
    await txn.insert('book_memo', {
      'id': memo.id,
      'server_id': memo.id,
      'owner_user_id': ownerUserId,
      'user_book_id': localUserBookId,
      'title': memo.title,
      'deleted_at': null,
      'created_at': memo.createdAt.toUtc().toIso8601String(),
      'updated_at': memo.updatedAt.toUtc().toIso8601String(),
      'is_dirty': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return memo.id;
  }

  Future<void> _upsertServerItemTxn(
    Transaction txn,
    int localMemoId,
    ServerBookMemoItem item,
  ) async {
    final existing = await txn.query(
      'book_memo_item',
      columns: ['id', 'is_dirty'],
      where: 'server_id = ?',
      whereArgs: [item.id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final localId = existing.single['id'] as int;
      final isDirty = existing.single['is_dirty'] == 1;
      if (!isDirty) {
        await txn.update(
          'book_memo_item',
          {
            'memo_id': localMemoId,
            'item_type': item.itemType,
            'start_page': item.startPage,
            'end_page': item.endPage,
            'content': item.content,
            'image_url': item.imageUrl,
            'is_important': item.isImportant ? 1 : 0,
            'sort_order': item.sortOrder,
            'deleted_at': null,
            'updated_at': item.updatedAt.toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
      return;
    }
    await txn.insert('book_memo_item', {
      'id': item.id,
      'server_id': item.id,
      'memo_id': localMemoId,
      'item_type': item.itemType,
      'start_page': item.startPage,
      'end_page': item.endPage,
      'content': item.content,
      'image_url': item.imageUrl,
      'is_important': item.isImportant ? 1 : 0,
      'sort_order': item.sortOrder,
      'deleted_at': null,
      'created_at': item.createdAt.toUtc().toIso8601String(),
      'updated_at': item.updatedAt.toUtc().toIso8601String(),
      'is_dirty': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int?> _findLocalMemoIdByServerId(
    Transaction txn,
    int serverMemoId,
  ) async {
    final rows = await txn.query(
      'book_memo',
      columns: ['id'],
      where: 'server_id = ?',
      whereArgs: [serverMemoId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['id'] as int;
  }

  Future<int?> _findLocalUserBookIdByServerId(
    Transaction txn,
    int serverUserBookId,
  ) async {
    final rows = await txn.query(
      'user_book',
      columns: ['user_book_id'],
      where: 'server_id = ? OR user_book_id = ?',
      whereArgs: [serverUserBookId, serverUserBookId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['user_book_id'] as int;
  }

  Future<List<int>> _localUserBookIdsForServerIds(
    Transaction txn,
    List<int> serverUserBookIds,
  ) async {
    if (serverUserBookIds.isEmpty) return const [];
    final placeholders = List.filled(serverUserBookIds.length, '?').join(', ');
    final rows = await txn.query(
      'user_book',
      columns: ['user_book_id'],
      where: 'server_id IN ($placeholders) OR user_book_id IN ($placeholders)',
      whereArgs: [...serverUserBookIds, ...serverUserBookIds],
    );
    return rows
        .map((row) => row['user_book_id'] as int)
        .toList(growable: false);
  }

  /// [activeUserBookIds]가 비어 있으면(이론상 발생하지 않아야 하지만,
  /// 방어적으로) 아무것도 지우지 않는다 — 빈 목록을 "책이 하나도 없다"로
  /// 오인해 전체 삭제로 번지는 사고를 막는다.
  Future<void> _deleteMissingMemosTxn(
    Transaction txn,
    int ownerUserId,
    List<int> activeUserBookIds,
    List<int> serverMemoIds,
  ) async {
    if (activeUserBookIds.isEmpty) return;
    final bookPlaceholders = List.filled(
      activeUserBookIds.length,
      '?',
    ).join(', ');
    if (serverMemoIds.isEmpty) {
      await txn.delete(
        'book_memo',
        where:
            'owner_user_id = ? AND server_id IS NOT NULL AND is_dirty = 0 '
            'AND user_book_id IN ($bookPlaceholders) '
            'AND NOT EXISTS (SELECT 1 FROM book_memo_item '
            'WHERE memo_id = book_memo.id AND is_dirty = 1)',
        whereArgs: [ownerUserId, ...activeUserBookIds],
      );
      return;
    }
    final memoPlaceholders = List.filled(serverMemoIds.length, '?').join(', ');
    await txn.delete(
      'book_memo',
      where:
          'owner_user_id = ? AND server_id IS NOT NULL '
          'AND server_id NOT IN ($memoPlaceholders) AND is_dirty = 0 '
          'AND user_book_id IN ($bookPlaceholders) '
          'AND NOT EXISTS (SELECT 1 FROM book_memo_item '
          'WHERE memo_id = book_memo.id AND is_dirty = 1)',
      whereArgs: [ownerUserId, ...serverMemoIds, ...activeUserBookIds],
    );
  }

  Future<void> _deleteMissingItemsTxn(
    Transaction txn,
    int ownerUserId,
    List<int> activeUserBookIds,
    List<int> serverItemIds,
  ) async {
    if (activeUserBookIds.isEmpty) return;
    final bookPlaceholders = List.filled(
      activeUserBookIds.length,
      '?',
    ).join(', ');
    if (serverItemIds.isEmpty) {
      await txn.delete(
        'book_memo_item',
        where:
            'server_id IS NOT NULL AND is_dirty = 0 AND memo_id IN '
            '(SELECT id FROM book_memo WHERE owner_user_id = ? '
            'AND user_book_id IN ($bookPlaceholders))',
        whereArgs: [ownerUserId, ...activeUserBookIds],
      );
      return;
    }
    final itemPlaceholders = List.filled(serverItemIds.length, '?').join(', ');
    await txn.delete(
      'book_memo_item',
      where:
          'server_id IS NOT NULL AND server_id NOT IN ($itemPlaceholders) '
          'AND is_dirty = 0 AND memo_id IN '
          '(SELECT id FROM book_memo WHERE owner_user_id = ? '
          'AND user_book_id IN ($bookPlaceholders))',
      whereArgs: [...serverItemIds, ownerUserId, ...activeUserBookIds],
    );
  }

  Future<int> _nextLocalId(Transaction txn, String table) async {
    final rows = await txn.rawQuery('SELECT MIN(id) AS min_id FROM $table');
    final current = rows.single['min_id'] as int?;
    return current != null && current <= 0 ? current - 1 : -1;
  }

  Future<void> _requireActiveMemo(
    Transaction txn, {
    required int ownerUserId,
    required int userBookId,
    required int memoId,
  }) async {
    final rows = await txn.query(
      'book_memo',
      columns: ['id'],
      where:
          'id = ? AND owner_user_id = ? AND user_book_id = ? '
          'AND deleted_at IS NULL',
      whereArgs: [memoId, ownerUserId, userBookId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Memo not found');
  }

  static BookMemo _memoFromRow(Map<String, Object?> row) {
    return BookMemo(
      id: row['id'] as int,
      serverId: row['server_id'] as int?,
      userBookId: row['user_book_id'] as int,
      title: row['title'] as String?,
      deletedAt: _parseNullable(row['deleted_at'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      isDirty: (row['is_dirty'] as int) == 1,
    );
  }

  static BookMemoItem _itemFromRow(Map<String, Object?> row) {
    final createdAt = DateTime.parse(row['created_at'] as String);
    final updatedAt = row['updated_at'] as String?;
    return BookMemoItem(
      id: row['id'] as int,
      serverId: row['server_id'] as int?,
      clientRequestId: row['client_request_id'] as String?,
      memoId: row['memo_id'] as int,
      type: BookMemoItemType.fromDb(row['item_type'] as String),
      startPage: row['start_page'] as int?,
      endPage: row['end_page'] as int?,
      content: row['content'] as String?,
      imageUrl: row['image_url'] as String?,
      isImportant: (row['is_important'] as int) == 1,
      sortOrder: row['sort_order'] as int,
      deletedAt: _parseNullable(row['deleted_at'] as String?),
      createdAt: createdAt,
      updatedAt: updatedAt == null ? createdAt : DateTime.parse(updatedAt),
      isDirty: (row['is_dirty'] as int) == 1,
    );
  }

  static DateTime? _parseNullable(String? value) =>
      value == null ? null : DateTime.parse(value);
}
