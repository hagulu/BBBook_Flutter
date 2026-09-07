import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';

import '../../bookshelf/data/bookshelf_database.dart';
import '../../record_sync/models/record_sync_payload.dart';
import '../models/tag_mapping.dart';

/// 태그(`tag`)/책-태그 매핑(`user_book_tag_map`) 로컬 DB 쿼리/쓰기 전담.
///
/// `tag`는 자체 dirty가 없다 — 태그 생성/복원은 매핑 추가 API의 부수 효과일
/// 뿐이라 별도로 push할 대상이 아니다([TagRepository] 참고). `user_book_tag_map`만
/// `is_dirty`로 로컬 우선 추가/삭제를 추적하며, [reconcileFullTags]/
/// [applyTagChanges](서버 조회 반영) 모두 dirty 매핑은 덮어쓰거나 삭제하지
/// 않는다.
///
/// 태그 매핑 생성 API(`POST .../tags`)는 태그 정보(id/name)만 돌려주고 매핑
/// 자체의 서버 ID는 알려주지 않는다. 그래서 push 확정 직후에도 매핑의
/// `server_id`는 비어 있을 수 있고, 그 값은 곧바로 이어지는 증분/전체
/// 동기화가 (`user_book_id`, `tag_id`) 조합으로 매칭해 채운다
/// ([_upsertServerTagMapTxn] 참고).
class TagDao {
  const TagDao();

  Future<DateTime?> getLastSyncedAtTag() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['last_synced_at_tag'],
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['value'] as String);
  }

  Future<List<int>> getDirtyMappingLocalIds() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'user_book_tag_map',
      columns: ['id'],
      where: 'is_dirty = 1',
    );
    return rows.map((r) => r['id'] as int).toList(growable: false);
  }

  Future<TagMapping?> getMappingByLocalId(int localId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'user_book_tag_map',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    return rows.isEmpty ? null : _mappingFromRow(rows.single);
  }

  Future<LocalTag?> getTagByLocalId(int localId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'tag',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    return rows.isEmpty ? null : _tagFromRow(rows.single);
  }

  /// 활성 태그를 사용 횟수, 마지막 사용 시각 순으로 반환한다. 태그 관리
  /// 시트의 추천과 검색이 같은 로컬 동기화 데이터를 보도록 여기에서 정렬한다.
  Future<List<LocalTag>> getTagsByUsage() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.rawQuery('''
      SELECT t.id, t.server_id, t.name,
             COUNT(m.id) AS usage_count,
             MAX(m.updated_at) AS last_used_at
      FROM tag t
      INNER JOIN user_book_tag_map m
        ON m.tag_id = t.id AND m.deleted_at IS NULL
      WHERE t.deleted_at IS NULL
      GROUP BY t.id, t.server_id, t.name
      ORDER BY usage_count DESC, last_used_at DESC, t.name COLLATE NOCASE ASC
    ''');
    return rows.map(_tagFromRow).toList(growable: false);
  }

  // ---------------------------------------------------------------------
  // 로컬 우선 추가/삭제
  // ---------------------------------------------------------------------

  /// 태그 추가를 로컬에 즉시 반영한다. 같은 이름의 활성 태그가 로컬에 있으면
  /// 재사용하고, soft delete된 태그면 복원한다(서버 `POST .../tags`의 규칙과
  /// 동일). 이 책에 이미 활성 매핑이 있으면(중복 추가) 새로 만들지 않고 그
  /// 매핑의 로컬 ID를 그대로 반환한다 — dirty 여부와 무관하게, push는
  /// [TagRepository.pushMapping]이 dirty 상태를 보고 알아서 스킵한다.
  ///
  /// 반환값은 이번에 만들었거나 재사용한 매핑의 로컬 ID다.
  Future<int> addTagLocal({
    required int userBookId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', '태그명이 비어있습니다.');
    }
    if (trimmed.length > 15) {
      throw ArgumentError.value(name, 'name', '태그명은 15자까지 입력할 수 있습니다.');
    }
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final tagId = await _findOrCreateLocalTagForAddTxn(txn, trimmed);
      final existing = await txn.query(
        'user_book_tag_map',
        columns: ['id'],
        where: 'user_book_id = ? AND tag_id = ? AND deleted_at IS NULL',
        whereArgs: [userBookId, tagId],
        limit: 1,
      );
      if (existing.isNotEmpty) return existing.single['id'] as int;

      final activeMappings = Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT COUNT(*) FROM user_book_tag_map '
          'WHERE user_book_id = ? AND deleted_at IS NULL',
          [userBookId],
        ),
      );
      if ((activeMappings ?? 0) >= 10) {
        throw ArgumentError.value(
          userBookId,
          'userBookId',
          '책당 태그는 최대 10개입니다.',
        );
      }

      final id = await _nextLocalId(txn, 'user_book_tag_map');
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.insert('user_book_tag_map', {
        'id': id,
        'server_id': null,
        'user_book_id': userBookId,
        'tag_id': tagId,
        'deleted_at': null,
        'created_at': now,
        'updated_at': now,
        'is_dirty': 1,
      });
      return id;
    });
  }

  /// 태그 삭제(soft delete)를 로컬에 즉시 반영한다. 이 책에 [tagLocalId]로
  /// 활성 매핑이 없으면(이미 삭제됨 등) null을 반환하고 아무 것도 하지
  /// 않는다.
  Future<int?> removeTagLocal({
    required int userBookId,
    required int tagLocalId,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'user_book_tag_map',
        columns: ['id'],
        where: 'user_book_id = ? AND tag_id = ? AND deleted_at IS NULL',
        whereArgs: [userBookId, tagLocalId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final id = rows.single['id'] as int;
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        'user_book_tag_map',
        {'deleted_at': now, 'updated_at': now, 'is_dirty': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    });
  }

  Future<int> _findOrCreateLocalTagForAddTxn(
    Transaction txn,
    String name,
  ) async {
    final active = await txn.query(
      'tag',
      columns: ['id'],
      where: 'name = ? AND deleted_at IS NULL',
      whereArgs: [name],
      limit: 1,
    );
    if (active.isNotEmpty) return active.single['id'] as int;

    final now = DateTime.now().toUtc().toIso8601String();
    final softDeleted = await txn.query(
      'tag',
      columns: ['id'],
      where: 'name = ? AND deleted_at IS NOT NULL',
      whereArgs: [name],
      orderBy: 'deleted_at DESC',
      limit: 1,
    );
    if (softDeleted.isNotEmpty) {
      final id = softDeleted.single['id'] as int;
      await txn.update(
        'tag',
        {'deleted_at': null, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    final id = await _nextLocalId(txn, 'tag');
    await txn.insert('tag', {
      'id': id,
      'server_id': null,
      'name': name,
      'deleted_at': null,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  // ---------------------------------------------------------------------
  // 서버 동기화(dirty push) 확정
  // ---------------------------------------------------------------------

  /// 매핑 생성 push(`POST .../tags`)가 성공한 뒤 확정 반영한다.
  ///
  /// [pendingTagLocalId]는 push를 시작할 때 이 매핑이 가리키던 로컬 태그
  /// ID다. [serverTagId]로 해석한 결과가 그 ID와 다르면(다른 기기가 같은
  /// 이름의 태그를 먼저 만들어 동기화로 이미 받아둔 경우 등, "같은 이름 태그
  /// 충돌") 이 태그를 참조하던 다른 매핑도 모두 새 태그 ID로 옮기고, 더는
  /// 아무 매핑도 참조하지 않게 된 이전 태그 행(아직 서버 ID가 없던 임시
  /// 행일 때만)을 정리한다.
  ///
  /// [capturedUpdatedAt]과 현재 로컬 `updated_at`이 같을 때만(그 사이 이
  /// 매핑에 새 로컬 편집 — 예: 삭제 — 이 없었을 때만) dirty를 해제한다.
  Future<void> confirmMappingCreated({
    required int mappingLocalId,
    required DateTime capturedUpdatedAt,
    required int pendingTagLocalId,
    required int serverTagId,
    required String serverTagName,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final resolvedTagId = await _resolveLocalTagForServerTxn(
        txn,
        serverId: serverTagId,
        nameForCreate: serverTagName,
      );
      if (resolvedTagId != pendingTagLocalId) {
        await txn.update(
          'user_book_tag_map',
          {'tag_id': resolvedTagId},
          where: 'tag_id = ?',
          whereArgs: [pendingTagLocalId],
        );
        final stillReferenced = await txn.query(
          'user_book_tag_map',
          columns: ['id'],
          where: 'tag_id = ?',
          whereArgs: [pendingTagLocalId],
          limit: 1,
        );
        if (stillReferenced.isEmpty) {
          await txn.delete(
            'tag',
            where: 'id = ? AND server_id IS NULL',
            whereArgs: [pendingTagLocalId],
          );
        }
      }

      final rows = await txn.query(
        'user_book_tag_map',
        columns: ['updated_at'],
        where: 'id = ?',
        whereArgs: [mappingLocalId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final current = DateTime.parse(rows.single['updated_at'] as String);
      if (current.isAtSameMomentAs(capturedUpdatedAt)) {
        await txn.update(
          'user_book_tag_map',
          {'is_dirty': 0},
          where: 'id = ?',
          whereArgs: [mappingLocalId],
        );
      }
    });
  }

  Future<void> purgeMapping(int localId) async {
    final db = await BookshelfDatabase.instance();
    await db.delete('user_book_tag_map', where: 'id = ?', whereArgs: [localId]);
  }

  /// 로컬 태그 행을 서버 태그(id/name)에 연결한다. `server_id`로 이미
  /// 연결된 행이 있으면 그 값을 갱신하고, 없으면 아직 서버 ID가 없는 같은
  /// 이름의(오프라인 생성) 태그 행을 병합해 연결한다(동시에 서로 다른
  /// 기기/시도가 같은 이름의 태그를 만들 때의 충돌 해소). 둘 다 없으면
  /// `id = server_id`로 새 행을 만든다.
  Future<int> _resolveLocalTagForServerTxn(
    Transaction txn, {
    required int serverId,
    required String nameForCreate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) async {
    final now = DateTime.now().toUtc();
    final createdIso = (createdAt ?? now).toUtc().toIso8601String();
    final updatedIso = (updatedAt ?? now).toUtc().toIso8601String();

    final byServerId = await txn.query(
      'tag',
      columns: ['id'],
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );
    if (byServerId.isNotEmpty) {
      final id = byServerId.single['id'] as int;
      await txn.update(
        'tag',
        {'name': nameForCreate, 'deleted_at': null, 'updated_at': updatedIso},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    final pendingByName = await txn.query(
      'tag',
      columns: ['id'],
      where: 'server_id IS NULL AND name = ?',
      whereArgs: [nameForCreate],
      limit: 1,
    );
    if (pendingByName.isNotEmpty) {
      final id = pendingByName.single['id'] as int;
      await txn.update(
        'tag',
        {
          'server_id': serverId,
          'name': nameForCreate,
          'deleted_at': null,
          'updated_at': updatedIso,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    await txn.insert('tag', {
      'id': serverId,
      'server_id': serverId,
      'name': nameForCreate,
      'deleted_at': null,
      'created_at': createdIso,
      'updated_at': updatedIso,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return serverId;
  }

  // ---------------------------------------------------------------------
  // 전체/증분 동기화 반영
  // ---------------------------------------------------------------------

  /// `/api/me/records` 전체 조회 결과로 태그/매핑 테이블을 맞춘다.
  ///
  /// [activeServerUserBookIds]는 같은 응답의 `books` 배열이다(소프트 삭제된
  /// 책은 이 응답에 없다 — `BookNoteDao.reconcileFullNotes`와 같은 이유로,
  /// 그 책의 매핑이 이번 응답에 없다고 곧장 지우면 안 되고 활성 책 범위로만
  /// 삭제를 제한한다).
  ///
  /// [requestedAt]은 이 요청을 보내기 *직전* 시각(UTC)이어야 한다.
  ///
  /// 상위 책을 아직 로컬에서 찾지 못한 매핑(orphan)이 하나라도 있으면
  /// `last_synced_at_tag`를 갱신하지 않는다 — 갱신해 버리면 이번에 놓친
  /// 매핑은 그 뒤로 다시 받을 방법이 없다(전체 조회는 항상 "현재 활성
  /// 전체"만 내려주므로 증분처럼 재시도할 `since`가 없다). 갱신을 건너뛰면
  /// 다음 [TagRepository.sync] 호출이 여전히 `since == null`(또는 이전
  /// 기준값)로 보고 전체 동기화를 다시 시도한다 — 책장 동기화가 그 사이
  /// 상위 책을 로컬에 채워 넣으면 자연히 해소된다
  /// (`applyTagChanges`의 orphan 처리와 같은 이유).
  Future<void> reconcileFullTags({
    required List<int> activeServerUserBookIds,
    required List<ServerTag> tags,
    required List<ServerTagMap> tagMaps,
    required DateTime requestedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final localActiveUserBookIds = await _localUserBookIdsForServerIds(
        txn,
        activeServerUserBookIds,
      );
      for (final tag in tags) {
        await _resolveLocalTagForServerTxn(
          txn,
          serverId: tag.id,
          nameForCreate: tag.name,
          createdAt: tag.createdAt,
          updatedAt: tag.updatedAt,
        );
      }
      var hasOrphan = false;
      for (final map in tagMaps) {
        final applied = await _upsertServerTagMapTxn(txn, map);
        if (!applied) {
          hasOrphan = true;
          developer.log(
            '[태그 전체 동기화] result=SKIP reason=orphan_tag_map '
            'serverMapId=${map.id} serverUserBookId=${map.userBookId} '
            'serverTagId=${map.tagId}',
          );
        }
      }

      final serverMapIds = tagMaps.map((m) => m.id).toList(growable: false);
      await _deleteMissingTagMapsTxn(txn, localActiveUserBookIds, serverMapIds);

      final serverTagIds = tags.map((t) => t.id).toList(growable: false);
      await _deleteMissingTagsTxn(txn, serverTagIds);

      if (!hasOrphan) {
        await txn.insert('sync_meta', {
          'key': 'last_synced_at_tag',
          'value': requestedAt.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// `/api/me/tags/sync/changes` 증분 동기화 결과를 반영한다. dirty 매핑은
  /// [reconcileFullTags]와 동일하게 보호한다. 부모 책을 로컬에서 찾지 못했거나
  /// (orphan) 참조하는 태그를 아직 모르는 매핑이 하나라도 있으면
  /// `last_synced_at_tag`를 앞으로 당기지 않고 지운다 — 다음 [TagRepository.sync]
  /// 호출이 전체 동기화(`/api/me/records`)로 대체되어 놓친 매핑을 되찾는다
  /// (`BookNoteDao.applyNoteChanges`의 orphan_memo 처리와 동일한 이유).
  Future<void> applyTagChanges({
    required List<ServerTag> upsertedTags,
    required List<int> deletedTagIds,
    required List<ServerTagMap> upsertedTagMaps,
    required List<int> deletedTagMapIds,
    required DateTime syncedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      for (final tag in upsertedTags) {
        await _resolveLocalTagForServerTxn(
          txn,
          serverId: tag.id,
          nameForCreate: tag.name,
          createdAt: tag.createdAt,
          updatedAt: tag.updatedAt,
        );
      }

      var hasOrphan = false;
      for (final map in upsertedTagMaps) {
        final applied = await _upsertServerTagMapTxn(txn, map);
        if (!applied) {
          hasOrphan = true;
          developer.log(
            '[태그 증분 동기화] result=SKIP reason=orphan_tag_map '
            'serverMapId=${map.id} serverUserBookId=${map.userBookId} '
            'serverTagId=${map.tagId}',
          );
        }
      }

      if (deletedTagMapIds.isNotEmpty) {
        final placeholders = List.filled(
          deletedTagMapIds.length,
          '?',
        ).join(', ');
        await txn.delete(
          'user_book_tag_map',
          where: 'server_id IN ($placeholders) AND is_dirty = 0',
          whereArgs: deletedTagMapIds,
        );
      }
      if (deletedTagIds.isNotEmpty) {
        final placeholders = List.filled(deletedTagIds.length, '?').join(', ');
        await txn.delete(
          'tag',
          where:
              'server_id IN ($placeholders) AND id NOT IN '
              '(SELECT tag_id FROM user_book_tag_map WHERE is_dirty = 1)',
          whereArgs: deletedTagIds,
        );
      }

      if (hasOrphan) {
        await txn.delete(
          'sync_meta',
          where: 'key = ?',
          whereArgs: ['last_synced_at_tag'],
        );
      } else {
        await txn.insert('sync_meta', {
          'key': 'last_synced_at_tag',
          'value': syncedAt.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// 서버 매핑 하나를 로컬에 반영한다. 상위 책(userBookId)이나 태그(tagId)를
  /// 로컬에서 아직 찾을 수 없으면(orphan) false를 반환하고 아무 것도 하지
  /// 않는다 — `applyTagChanges`/`reconcileFullTags`가 매번 태그를 매핑보다
  /// 먼저 처리하므로, 같은 응답에서 함께 내려온 새 태그는 이 시점엔 이미
  /// 로컬에 있다.
  Future<bool> _upsertServerTagMapTxn(Transaction txn, ServerTagMap map) async {
    final localUserBookId = await _findLocalUserBookIdByServerId(
      txn,
      map.userBookId,
    );
    if (localUserBookId == null) return false;
    final localTagRows = await txn.query(
      'tag',
      columns: ['id'],
      where: 'server_id = ?',
      whereArgs: [map.tagId],
      limit: 1,
    );
    if (localTagRows.isEmpty) return false;
    final localTagId = localTagRows.single['id'] as int;

    final existing = await txn.query(
      'user_book_tag_map',
      columns: ['id', 'is_dirty'],
      where: 'server_id = ?',
      whereArgs: [map.id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final localId = existing.single['id'] as int;
      final isDirty = existing.single['is_dirty'] == 1;
      if (!isDirty) {
        await txn.update(
          'user_book_tag_map',
          {
            'user_book_id': localUserBookId,
            'tag_id': localTagId,
            'deleted_at': null,
            'updated_at': map.updatedAt.toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
      return true;
    }

    // 서버 매핑 ID를 아직 모르는 로컬 행(우리가 만든 POST push는 확정됐지만
    // 매핑 자체의 서버 ID는 응답으로 받지 못했던 경우)을 (책, 태그) 조합으로
    // 찾아 연결한다.
    final pending = await txn.query(
      'user_book_tag_map',
      columns: ['id', 'deleted_at'],
      where: 'user_book_id = ? AND tag_id = ? AND server_id IS NULL',
      whereArgs: [localUserBookId, localTagId],
      limit: 1,
    );
    if (pending.isNotEmpty) {
      final localId = pending.single['id'] as int;
      // 로컬에서 아직 삭제 표시되지 않았으면(=이 매핑의 생성 push를 기다리고
      // 있었을 뿐) 서버가 이미 알고 있다는 뜻이므로 여기서 dirty를 완전히
      // 해제한다 — 그러지 않으면 매핑 생성 push(409로 계속 거절됨)가
      // 매 동기화마다 무의미하게 재시도된다. 이미 로컬에서 삭제
      // 표시됐으면(삭제 push가 아직 남음) 서버 ID만 채우고 dirty는 그대로
      // 둔다.
      final deletedLocally = pending.single['deleted_at'] != null;
      await txn.update(
        'user_book_tag_map',
        {
          'server_id': map.id,
          if (!deletedLocally) ...{
            'updated_at': map.updatedAt.toUtc().toIso8601String(),
            'is_dirty': 0,
          },
        },
        where: 'id = ?',
        whereArgs: [localId],
      );
      return true;
    }

    await txn.insert('user_book_tag_map', {
      'id': map.id,
      'server_id': map.id,
      'user_book_id': localUserBookId,
      'tag_id': localTagId,
      'deleted_at': null,
      'created_at': map.createdAt.toUtc().toIso8601String(),
      'updated_at': map.updatedAt.toUtc().toIso8601String(),
      'is_dirty': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<void> _deleteMissingTagMapsTxn(
    Transaction txn,
    List<int> localActiveUserBookIds,
    List<int> serverMapIds,
  ) async {
    if (localActiveUserBookIds.isEmpty) return;
    final bookPlaceholders = List.filled(
      localActiveUserBookIds.length,
      '?',
    ).join(', ');
    if (serverMapIds.isEmpty) {
      await txn.delete(
        'user_book_tag_map',
        where:
            'server_id IS NOT NULL AND is_dirty = 0 '
            'AND user_book_id IN ($bookPlaceholders)',
        whereArgs: localActiveUserBookIds,
      );
      return;
    }
    final mapPlaceholders = List.filled(serverMapIds.length, '?').join(', ');
    await txn.delete(
      'user_book_tag_map',
      where:
          'server_id IS NOT NULL AND server_id NOT IN ($mapPlaceholders) '
          'AND is_dirty = 0 AND user_book_id IN ($bookPlaceholders)',
      whereArgs: [...serverMapIds, ...localActiveUserBookIds],
    );
  }

  Future<void> _deleteMissingTagsTxn(
    Transaction txn,
    List<int> serverTagIds,
  ) async {
    const dirtyReferenceClause =
        'id NOT IN (SELECT tag_id FROM user_book_tag_map WHERE is_dirty = 1)';
    if (serverTagIds.isEmpty) {
      await txn.delete(
        'tag',
        where: 'server_id IS NOT NULL AND $dirtyReferenceClause',
      );
      return;
    }
    final placeholders = List.filled(serverTagIds.length, '?').join(', ');
    await txn.delete(
      'tag',
      where:
          'server_id IS NOT NULL AND server_id NOT IN ($placeholders) '
          'AND $dirtyReferenceClause',
      whereArgs: serverTagIds,
    );
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

  Future<int> _nextLocalId(Transaction txn, String table) async {
    final rows = await txn.rawQuery('SELECT MIN(id) AS min_id FROM $table');
    final current = rows.single['min_id'] as int?;
    return current != null && current <= 0 ? current - 1 : -1;
  }

  // ---------------------------------------------------------------------
  // 로컬 → 서버 저장 모드 재전환 Import 전용
  // ---------------------------------------------------------------------

  /// Import 대상 조회: 활성 태그 전체.
  Future<List<LocalTag>> getAllActiveTags() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query('tag', where: 'deleted_at IS NULL');
    return rows.map(_tagFromRow).toList(growable: false);
  }

  /// Import 대상 조회: 활성 책-태그 매핑 전체.
  Future<List<TagMapping>> getAllActiveMappings() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query('user_book_tag_map', where: 'deleted_at IS NULL');
    return rows.map(_mappingFromRow).toList(growable: false);
  }

  /// Import `/complete` 성공 후에만 태그/매핑의 서버 ID를 확정한다(청크
  /// 응답 즉시 반영하지 않는 이유는 `BookshelfDao.applyImportResults` 참고).
  /// `tag`는 자체 dirty 추적이 없어 여기서도 건드리지 않는다.
  ///
  /// [executor]는 다른 도메인과 하나의 트랜잭션을 공유하기 위한 것이다
  /// (`BookshelfDao.applyImportResults` 문서 참고).
  Future<void> applyImportResults(
    DatabaseExecutor executor, {
    required Map<int, int> tagServerIdByLocalId,
    required Map<int, int> mappingServerIdByLocalId,
  }) async {
    for (final entry in tagServerIdByLocalId.entries) {
      await executor.update(
        'tag',
        {'server_id': entry.value},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
    for (final entry in mappingServerIdByLocalId.entries) {
      await executor.update(
        'user_book_tag_map',
        {'server_id': entry.value, 'is_dirty': 0},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
  }

  static TagMapping _mappingFromRow(Map<String, Object?> row) {
    return TagMapping(
      id: row['id'] as int,
      serverId: row['server_id'] as int?,
      userBookId: row['user_book_id'] as int,
      tagId: row['tag_id'] as int,
      deletedAt: _parseNullable(row['deleted_at'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      isDirty: (row['is_dirty'] as int) == 1,
    );
  }

  static LocalTag _tagFromRow(Map<String, Object?> row) {
    return LocalTag(
      id: row['id'] as int,
      serverId: row['server_id'] as int?,
      name: row['name'] as String,
    );
  }

  static DateTime? _parseNullable(String? value) =>
      value == null ? null : DateTime.parse(value);
}
