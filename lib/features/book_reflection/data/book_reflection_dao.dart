import 'dart:convert';
import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../bookshelf/data/bookshelf_database.dart';
import '../../record_sync/models/record_sync_payload.dart';
import '../models/book_reflection.dart';

/// 독후감 로컬 DB 쿼리/쓰기 전담.
///
/// `id`는 화면이 계속 참조하는 로컬 PK이고 오프라인 생성 시 음수일 수 있다.
/// 서버 PK는 `server_id`, CREATE 멱등 키는 `client_request_id`에 분리해
/// 노트와 같은 로컬 우선 + dirty push 구조를 유지한다.
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
      where: 'owner_user_id = ? AND user_book_id = ? AND deleted_at IS NULL',
      whereArgs: [ownerUserId, userBookId],
      // 로컬 신규 행은 음수 PK라 id만으로 정렬하지 않고 생성 시각을 기준으로 한다.
      orderBy: 'created_at DESC, id DESC',
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

  Future<BookReflection> createLocal({
    required int ownerUserId,
    required int userBookId,
    required BookReflectionDraft draft,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final id = await _nextLocalId(txn);
      final now = DateTime.now().toUtc().toIso8601String();
      final values = <String, Object?>{
        'id': id,
        'server_id': null,
        'client_request_id': const Uuid().v4(),
        'owner_user_id': ownerUserId,
        'user_book_id': userBookId,
        'reflection_type': 'USER_WRITTEN',
        'title': draft.title,
        'content_json': jsonEncode(draft.contentJson),
        'content_text': draft.contentText,
        'is_public': draft.isPublic ? 1 : 0,
        'is_hidden': 0,
        'deleted_at': null,
        'created_at': now,
        'updated_at': now,
        'is_dirty': 1,
      };
      await txn.insert('book_reflection', values);
      return _reflectionFromRow(values);
    });
  }

  Future<BookReflection> updateLocal({
    required int ownerUserId,
    required int userBookId,
    required int reflectionId,
    required BookReflectionDraft draft,
  }) async {
    final db = await BookshelfDatabase.instance();
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await db.update(
      'book_reflection',
      {
        'title': draft.title,
        'content_json': jsonEncode(draft.contentJson),
        'content_text': draft.contentText,
        'is_public': draft.isPublic ? 1 : 0,
        'updated_at': now,
        'is_dirty': 1,
      },
      where:
          'id = ? AND owner_user_id = ? AND user_book_id = ? '
          'AND deleted_at IS NULL AND is_hidden = 0',
      whereArgs: [reflectionId, ownerUserId, userBookId],
    );
    if (count != 1) throw StateError('Reflection not found');
    final rows = await db.query(
      'book_reflection',
      where: 'id = ?',
      whereArgs: [reflectionId],
      limit: 1,
    );
    return _reflectionFromRow(rows.single);
  }

  Future<BookReflection> updateVisibilityLocal({
    required int ownerUserId,
    required int userBookId,
    required int reflectionId,
    required bool isPublic,
  }) async {
    final db = await BookshelfDatabase.instance();
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await db.update(
      'book_reflection',
      {'is_public': isPublic ? 1 : 0, 'updated_at': now},
      where:
          'id = ? AND owner_user_id = ? AND user_book_id = ? '
          'AND deleted_at IS NULL AND is_hidden = 0',
      whereArgs: [reflectionId, ownerUserId, userBookId],
    );
    if (count != 1) throw StateError('Reflection not found');
    final rows = await db.query(
      'book_reflection',
      where: 'id = ?',
      whereArgs: [reflectionId],
      limit: 1,
    );
    return _reflectionFromRow(rows.single);
  }

  Future<BookReflection> markDeletedLocal({
    required int ownerUserId,
    required int userBookId,
    required int reflectionId,
  }) async {
    final db = await BookshelfDatabase.instance();
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await db.update(
      'book_reflection',
      {'deleted_at': now, 'updated_at': now, 'is_dirty': 1},
      where:
          'id = ? AND owner_user_id = ? AND user_book_id = ? '
          'AND deleted_at IS NULL',
      whereArgs: [reflectionId, ownerUserId, userBookId],
    );
    if (count != 1) throw StateError('Reflection not found');
    final rows = await db.query(
      'book_reflection',
      where: 'id = ?',
      whereArgs: [reflectionId],
      limit: 1,
    );
    return _reflectionFromRow(rows.single);
  }

  Future<List<BookReflection>> getDirty() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_reflection',
      where: 'is_dirty = 1',
      orderBy: 'updated_at ASC, id ASC',
    );
    return rows.map(_reflectionFromRow).toList(growable: false);
  }

  Future<BookReflection?> getByLocalId(int reflectionId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_reflection',
      where: 'id = ?',
      whereArgs: [reflectionId],
      limit: 1,
    );
    return rows.isEmpty ? null : _reflectionFromRow(rows.single);
  }

  /// 서버 PK([BookReflection.serverId])로 로컬 행을 찾는다. 이 기기에서
  /// 직접 작성한 행은 push가 끝난 뒤에도 로컬 PK([BookReflection.id])를
  /// 그대로 유지하고 `server_id`만 채우므로("내가 작성한 콘텐츠" 목록처럼
  /// 서버 ID만 갖고 있는 화면에서 로컬 상세로 연결할 때 이 조회가 필요하다.
  Future<BookReflection?> getByServerId({
    required int ownerUserId,
    required int serverId,
  }) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_reflection',
      where: 'server_id = ? AND owner_user_id = ? AND deleted_at IS NULL',
      whereArgs: [serverId, ownerUserId],
      limit: 1,
    );
    return rows.isEmpty ? null : _reflectionFromRow(rows.single);
  }

  Future<void> confirmDelete({
    required int localId,
    required DateTime capturedUpdatedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.delete(
      'book_reflection',
      where: 'id = ? AND updated_at = ? AND deleted_at IS NOT NULL',
      whereArgs: [localId, capturedUpdatedAt.toUtc().toIso8601String()],
    );
  }

  /// 반환값은 서버 응답이 로컬 행에 실제로 반영됐는지 여부. push가 오가는
  /// 동안 새 편집이 들어왔으면 `server_id`만 채우고 본문은 그대로 둔다 —
  /// 그 경우 로컬 본문은 아직 업로드 전 이미지 경로를 들고 있으므로,
  /// 호출부(`BookReflectionRepository`)가 이 값을 보고 이미지 매칭 기록을
  /// 건너뛰어야 한다.
  Future<bool> confirmPush({
    required int localId,
    required DateTime capturedUpdatedAt,
    required BookReflectionServerResult result,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'book_reflection',
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final currentUpdatedAt = DateTime.parse(
        rows.single['updated_at'] as String,
      );
      if (!currentUpdatedAt.isAtSameMomentAs(capturedUpdatedAt)) {
        await txn.update(
          'book_reflection',
          {'server_id': result.id},
          where: 'id = ?',
          whereArgs: [localId],
        );
        return false;
      }
      await txn.update(
        'book_reflection',
        {
          'server_id': result.id,
          'reflection_type':
              result.reflectionType ?? rows.single['reflection_type'],
          'title': result.title,
          'content_json': jsonEncode(result.contentJson),
          'content_text': result.contentText,
          'is_public': result.isPublic ? 1 : 0,
          'created_at': result.createdAt.toUtc().toIso8601String(),
          'updated_at': result.updatedAt.toUtc().toIso8601String(),
          'is_dirty': 0,
        },
        where: 'id = ?',
        whereArgs: [localId],
      );
      return true;
    });
  }

  // ---------------------------------------------------------------------
  // 본문 이미지 로컬 사본 매칭(reflection_image_local)
  // ---------------------------------------------------------------------

  /// 한 독후감의 "서버 이미지 URL → 로컬 사본 상대 경로" 매칭.
  /// 화면은 이 값으로 본문 이미지를 로컬 파일로 바꿔 표시한다.
  Future<Map<String, String>> findLocalImagePaths(int reflectionId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'reflection_image_local',
      columns: ['remote_image_url', 'local_image_path'],
      where: 'reflection_id = ?',
      whereArgs: [reflectionId],
    );
    return {
      for (final row in rows)
        row['remote_image_url'] as String: row['local_image_path'] as String,
    };
  }

  /// 한 독후감의 매칭을 [mappings] 내용으로 맞춘다(없는 URL 행은 삭제).
  /// 본문에서 지워진 이미지의 매칭이 남아 로컬 파일이 영영 정리되지 않는
  /// 것을 막는다.
  Future<void> replaceLocalImages({
    required int reflectionId,
    required Map<String, String> mappings,
  }) async {
    final db = await BookshelfDatabase.instance();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      if (mappings.isEmpty) {
        await txn.delete(
          'reflection_image_local',
          where: 'reflection_id = ?',
          whereArgs: [reflectionId],
        );
        return;
      }
      final placeholders = List.filled(mappings.length, '?').join(', ');
      await txn.delete(
        'reflection_image_local',
        where: 'reflection_id = ? AND remote_image_url NOT IN ($placeholders)',
        whereArgs: [reflectionId, ...mappings.keys],
      );
      for (final entry in mappings.entries) {
        await txn.insert('reflection_image_local', {
          'reflection_id': reflectionId,
          'remote_image_url': entry.key,
          'local_image_path': entry.value,
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> deleteLocalImagesFor(int reflectionId) async {
    final db = await BookshelfDatabase.instance();
    await db.delete(
      'reflection_image_local',
      where: 'reflection_id = ?',
      whereArgs: [reflectionId],
    );
  }

  /// 매칭 전체(orphan 정리·유실 확인용).
  Future<List<ReflectionImageLink>> getAllLocalImages() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query('reflection_image_local');
    return rows
        .map(
          (row) => ReflectionImageLink(
            reflectionId: row['reflection_id'] as int,
            remoteImageUrl: row['remote_image_url'] as String,
            localImagePath: row['local_image_path'] as String,
          ),
        )
        .toList(growable: false);
  }

  /// 독후감 행이 사라졌는데 남아 있는 매칭을 지운다.
  ///
  /// `reflection_image_local`은 일부러 외래 키를 걸지 않으므로
  /// (`BookshelfDatabase._createReflectionImageLocalTable` 참고) 동기화가
  /// 독후감을 지워도 매칭은 남는다. 그대로 두면 orphan 정리가 그 매칭을
  /// "아직 쓰는 파일"로 보고 로컬 파일을 영원히 남긴다.
  Future<void> deleteOrphanLocalImages() async {
    final db = await BookshelfDatabase.instance();
    await db.delete(
      'reflection_image_local',
      where:
          'NOT EXISTS (SELECT 1 FROM book_reflection '
          'WHERE book_reflection.id = reflection_image_local.reflection_id '
          'AND book_reflection.deleted_at IS NULL)',
    );
  }

  /// 이미지 hydration이 훑을 대상(삭제되지 않은 독후감 전체).
  Future<List<BookReflection>> getAllActive() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_reflection',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC, id DESC',
    );
    return rows.map(_reflectionFromRow).toList(growable: false);
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
  /// [BookNoteDao.reconcileFullNotes]와 같은 이유로, "책은 그대로 있는데
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
  /// [BookNoteDao.applyNoteChanges]와 같은 구조 — 부모(user_book)를 로컬에서
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
          where: 'server_id IN ($placeholders) AND is_dirty = 0',
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
      where: 'server_id = ? OR (server_id IS NULL AND id = ?)',
      whereArgs: [reflection.id, reflection.id],
      limit: 1,
    );
    if (existing.isNotEmpty && existing.single['is_dirty'] == 1) {
      return;
    }
    final localId = existing.isEmpty
        ? reflection.id
        : existing.single['id'] as int;
    await txn.insert('book_reflection', {
      'id': localId,
      'server_id': reflection.id,
      'client_request_id': null,
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
          'owner_user_id = ? '
          'AND (server_id IS NULL OR server_id NOT IN ($reflectionPlaceholders)) '
          'AND is_dirty = 0 AND user_book_id IN ($bookPlaceholders)',
      whereArgs: [ownerUserId, ...serverReflectionIds, ...activeUserBookIds],
    );
  }

  static BookReflection _reflectionFromRow(Map<String, Object?> row) {
    final contentJson = row['content_json'] as String?;
    return BookReflection(
      id: row['id'] as int,
      serverId: row['server_id'] as int?,
      clientRequestId: row['client_request_id'] as String?,
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

  Future<int> _nextLocalId(Transaction txn) async {
    final rows = await txn.rawQuery(
      'SELECT MIN(id) AS min_id FROM book_reflection',
    );
    final current = rows.single['min_id'] as int?;
    return current != null && current <= 0 ? current - 1 : -1;
  }

  // ---------------------------------------------------------------------
  // 로컬 → 서버 저장 모드 재전환 Import 전용
  // ---------------------------------------------------------------------

  /// Import 대상 조회: 활성이고 숨김 처리되지 않은 독후감 전체. 관리자가
  /// 숨긴 독후감은 이미 title/contentJson/contentText가 null인 채로
  /// 로컬에 반영돼 있어(서버 정책), Import 신규/복구 필수값을 만족할 수
  /// 없으므로 애초에 대상에서 뺀다.
  Future<List<BookReflection>> getAllActiveForImport({
    required int ownerUserId,
  }) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_reflection',
      where: 'owner_user_id = ? AND deleted_at IS NULL AND is_hidden = 0',
      whereArgs: [ownerUserId],
    );
    return rows.map(_reflectionFromRow).toList(growable: false);
  }

  /// Import 전 멱등 키를 한 번 발급해 고정한다([BookReflection.clientRequestId]가
  /// 없는 행 — 서버 동기화로만 내려온 옛 데이터 등). 이미 있는 값은 건드리지 않는다.
  Future<void> ensureClientRequestIds() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_reflection',
      columns: ['id'],
      where: 'client_request_id IS NULL',
    );
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      for (final row in rows) {
        await txn.update(
          'book_reflection',
          {'client_request_id': const Uuid().v4()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
  }

  /// Import `/complete` 성공 후에만 독후감의 서버 ID와 최종 본문(placeholder가
  /// 서버 URL로 치환된 결과)을 확정하고, 새로 업로드한 이미지의 로컬↔서버
  /// 매칭([reflection_image_local])을 남긴다 — 전환 뒤에도 방금 올린
  /// 사진을 오프라인에서 계속 로컬 파일로 보여주기 위함이다(청크 응답 즉시
  /// 반영하지 않는 이유는 `BookshelfDao.applyImportResults` 참고).
  ///
  /// [executor]는 다른 도메인과 하나의 트랜잭션을 공유하기 위한 것이다
  /// ([BookshelfDao.applyImportResults] 문서 참고).
  Future<void> applyImportResults(
    DatabaseExecutor executor, {
    required Map<int, ReflectionImportResult> resultsByLocalId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final entry in resultsByLocalId.entries) {
      final result = entry.value;
      await executor.update(
        'book_reflection',
        {
          'server_id': result.serverId,
          'is_dirty': 0,
          if (result.finalContentJson != null)
            'content_json': jsonEncode(result.finalContentJson),
        },
        where: 'id = ?',
        whereArgs: [entry.key],
      );
      for (final image in result.uploadedImages) {
        await executor.insert('reflection_image_local', {
          'reflection_id': entry.key,
          'remote_image_url': image.remoteUrl,
          'local_image_path': image.localImagePath,
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }
}

/// Import `/complete` 확정 시 독후감 한 건에 반영할 결과
/// ([BookReflectionDao.applyImportResults]). [finalContentJson]은
/// `local://` placeholder가 하나라도 있었을 때만 채운다(치환된 최종 본문).
typedef ReflectionImportResult = ({
  int serverId,
  Map<String, dynamic>? finalContentJson,
  List<({String remoteUrl, String localImagePath})> uploadedImages,
});
