import 'dart:convert';
import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';

import '../../bookshelf/data/bookshelf_database.dart';
import '../../record_sync/models/record_sync_payload.dart';
import '../models/book_reflection.dart';

/// 독후감 로컬 DB 쿼리/쓰기 전담.
///
/// [BookMemoDao]와 달리 `book_reflection.id`는 지금은 항상 서버 ID와 같다
/// (로컬 전용 오프라인 생성 경로가 아직 없다 — 편집기 기능 붙일 때 `server_id`
/// 컬럼 분리 여부를 다시 검토해야 한다). 그래서 이 DAO는 조회와 서버 조회
/// 결과 반영(전체/증분 동기화)만 담당하고, `is_dirty`를 세우는 로컬 쓰기
/// 경로는 아직 없다.
class BookReflectionDao {
  const BookReflectionDao();

  /// 주의: `/api/me/records`·`/api/me/reflections/sync/changes` 응답
  /// 스키마(`ServerBookReflection`)에는 DRAFT/PUBLISHED 구분(`status`)이 없어
  /// 이 목록이 초안을 걸러내지 못할 수 있다. 반면 웹이 쓰는 전용 목록 API
  /// (`GET /api/me/books/{userBookId}/reflections`)는 PUBLISHED만 반환한다고
  /// 명시돼 있다 — DRAFT/AI_GENERATED는 애초에 포팅 문서에서도 "확인 필요"로
  /// 남겨둔 항목이라(reflection-editor.md) 이 자리에서 임의로 걸러내지
  /// 않았다. 서버가 이 두 API에도 PUBLISHED만 내려주는지, 아니면 로컬 스키마에
  /// `status`를 추가해야 하는지는 백엔드 확인이 필요하다.
  Future<List<BookReflection>> findByUserBook({
    required int ownerUserId,
    required int userBookId,
  }) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_reflection',
      where:
          'owner_user_id = ? AND user_book_id = ? AND deleted_at IS NULL',
      whereArgs: [ownerUserId, userBookId],
      // 서버 목록 API(`GET /api/me/books/{userBookId}/reflections`)와 같은
      // 정렬(최신순 id DESC) — `id`가 곧 서버 ID이므로 그대로 일치한다.
      orderBy: 'id DESC',
    );
    return rows.map(_reflectionFromRow).toList(growable: false);
  }

  Future<BookReflection?> findDetail({
    required int ownerUserId,
    required int userBookId,
    required int reflectionId,
  }) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_reflection',
      where:
          'id = ? AND owner_user_id = ? AND user_book_id = ? '
          'AND deleted_at IS NULL',
      whereArgs: [reflectionId, ownerUserId, userBookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _reflectionFromRow(rows.single);
  }

  // ---------------------------------------------------------------------
  // 서버 동기화 전용
  // ---------------------------------------------------------------------

  Future<DateTime?> getLastSyncedAtReflection() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['last_synced_at_reflection'],
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['value'] as String);
  }

  /// `/api/me/records` 전체 조회 결과로 독후감 테이블을 맞춘다: 서버에 있는
  /// 행은 upsert, 서버에 없는(로컬에만 남은) 비-dirty 행은 삭제.
  ///
  /// [activeUserBookIds]는 같은 `/api/me/records` 응답의 `books` 배열이다.
  /// [BookMemoDao.reconcileFullMemo]와 같은 이유로, "책은 그대로 있는데
  /// 독후감만 없어졌을 때만" 삭제 대상으로 본다 — 소프트 삭제된 책장
  /// 항목의 독후감은 이번 응답에 아예 포함되지 않으므로("서버에서
  /// 삭제됨"으로 오인하면 안 됨).
  Future<void> reconcileFullReflection({
    required int ownerUserId,
    required List<int> activeUserBookIds,
    required List<ServerBookReflection> reflections,
    required DateTime requestedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final localActiveUserBookIds = await _localUserBookIdsForServerIds(
        txn,
        activeUserBookIds,
      );
      for (final reflection in reflections) {
        await _upsertServerReflectionTxn(txn, ownerUserId, reflection);
      }

      final serverReflectionIds = reflections
          .map((r) => r.id)
          .toList(growable: false);
      await _deleteMissingReflectionsTxn(
        txn,
        ownerUserId,
        localActiveUserBookIds,
        serverReflectionIds,
      );

      await txn.insert('sync_meta', {
        'key': 'last_synced_at_reflection',
        'value': requestedAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// `/api/me/reflections/sync/changes` 증분 동기화 결과를 반영한다.
  /// [BookMemoDao.applyMemoChanges]와 같은 구조 — 부모(user_book)를 로컬에서
  /// 찾지 못한 독후감(orphan)이 있으면 기준값을 앞으로 당기지 않고 지워
  /// 다음 [BookReflectionRepository.sync] 호출이 전체 동기화로 대체되게 한다.
  Future<void> applyReflectionChanges({
    required int ownerUserId,
    required List<ServerBookReflection> upsertedReflections,
    required List<int> deletedReflectionIds,
    required DateTime syncedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      var hasOrphan = false;
      for (final reflection in upsertedReflections) {
        final localUserBookId = await _findLocalUserBookIdByServerId(
          txn,
          reflection.userBookId,
        );
        if (localUserBookId == null) {
          hasOrphan = true;
          developer.log(
            '[독후감 증분 동기화] result=SKIP reason=orphan_reflection '
            'serverReflectionId=${reflection.id} '
            'serverUserBookId=${reflection.userBookId}',
          );
          continue;
        }
        await _upsertServerReflectionTxn(txn, ownerUserId, reflection);
      }

      if (deletedReflectionIds.isNotEmpty) {
        final placeholders = List.filled(
          deletedReflectionIds.length,
          '?',
        ).join(', ');
        await txn.delete(
          'book_reflection',
          where: 'id IN ($placeholders) AND is_dirty = 0',
          whereArgs: deletedReflectionIds,
        );
      }

      if (hasOrphan) {
        await txn.delete(
          'sync_meta',
          where: 'key = ?',
          whereArgs: ['last_synced_at_reflection'],
        );
      } else {
        await txn.insert('sync_meta', {
          'key': 'last_synced_at_reflection',
          'value': syncedAt.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> _upsertServerReflectionTxn(
    Transaction txn,
    int ownerUserId,
    ServerBookReflection reflection,
  ) async {
    final localUserBookId =
        await _findLocalUserBookIdByServerId(txn, reflection.userBookId) ??
        reflection.userBookId;
    final existing = await txn.query(
      'book_reflection',
      columns: ['id', 'is_dirty'],
      where: 'id = ?',
      whereArgs: [reflection.id],
      limit: 1,
    );
    if (existing.isNotEmpty && existing.single['is_dirty'] == 1) {
      // 아직 로컬 편집 push 기능이 없어 실제로는 항상 false지만, 미래의
      // 로컬 편집 기능과의 정합성을 위해 dirty 행은 그대로 보호한다.
      return;
    }
    await txn.insert('book_reflection', {
      'id': reflection.id,
      'owner_user_id': ownerUserId,
      'user_book_id': localUserBookId,
      'reflection_type': reflection.reflectionType,
      'title': reflection.title,
      'content_json': reflection.contentJson == null
          ? null
          : jsonEncode(reflection.contentJson),
      'content_text': reflection.contentText,
      'is_public': reflection.isPublic ? 1 : 0,
      'is_hidden': reflection.isHidden ? 1 : 0,
      'deleted_at': null,
      'created_at': reflection.createdAt.toUtc().toIso8601String(),
      'updated_at': reflection.updatedAt.toUtc().toIso8601String(),
      'is_dirty': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
  Future<void> _deleteMissingReflectionsTxn(
    Transaction txn,
    int ownerUserId,
    List<int> activeUserBookIds,
    List<int> serverReflectionIds,
  ) async {
    if (activeUserBookIds.isEmpty) return;
    final bookPlaceholders = List.filled(
      activeUserBookIds.length,
      '?',
    ).join(', ');
    if (serverReflectionIds.isEmpty) {
      await txn.delete(
        'book_reflection',
        where:
            'owner_user_id = ? AND is_dirty = 0 '
            'AND user_book_id IN ($bookPlaceholders)',
        whereArgs: [ownerUserId, ...activeUserBookIds],
      );
      return;
    }
    final reflectionPlaceholders = List.filled(
      serverReflectionIds.length,
      '?',
    ).join(', ');
    await txn.delete(
      'book_reflection',
      where:
          'owner_user_id = ? AND id NOT IN ($reflectionPlaceholders) '
          'AND is_dirty = 0 AND user_book_id IN ($bookPlaceholders)',
      whereArgs: [ownerUserId, ...serverReflectionIds, ...activeUserBookIds],
    );
  }

  static BookReflection _reflectionFromRow(Map<String, Object?> row) {
    final contentJson = row['content_json'] as String?;
    return BookReflection(
      id: row['id'] as int,
      userBookId: row['user_book_id'] as int,
      reflectionType: row['reflection_type'] as String,
      title: row['title'] as String?,
      contentJson: contentJson == null
          ? null
          : jsonDecode(contentJson) as Map<String, dynamic>,
      contentText: row['content_text'] as String?,
      isPublic: (row['is_public'] as int) == 1,
      isHidden: (row['is_hidden'] as int) == 1,
      deletedAt: _parseNullable(row['deleted_at'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      isDirty: (row['is_dirty'] as int) == 1,
    );
  }

  static DateTime? _parseNullable(String? value) =>
      value == null ? null : DateTime.parse(value);
}
