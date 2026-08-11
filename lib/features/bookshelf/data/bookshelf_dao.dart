import 'package:sqflite/sqflite.dart';

import '../models/book_item.dart';
import '../models/book_status.dart';
import '../models/book_tag.dart';
import '../models/finished_filter.dart';
import 'bookshelf_database.dart';

/// 책장 로컬 DB 쿼리/쓰기 전담.
///
/// `is_dirty = 1`인 로컬 행은 [reconcile](전체 동기화)/[applyChanges](증분
/// 동기화) 모두 서버 데이터로 덮어쓰거나 삭제하지 않는다 — [applyLocalEdit]로
/// 표시된 책 기록 화면의 로컬 우선 수정을 동기화가 지우지 않게 하기 위함이다.
/// dirty 행은 [confirmPush](서버 push 성공)나 [resolveConflict](409 충돌)를
/// 통해서만 해제된다.
class BookshelfDao {
  const BookshelfDao();

  Future<BookItem?> getById(int userBookId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'user_book',
      where: 'user_book_id = ?',
      whereArgs: [userBookId],
    );
    if (rows.isEmpty) return null;
    final items = await _attachTags(db, rows);
    return items.first;
  }

  Future<List<BookItem>> getByStatuses(List<BookStatus> statuses) async {
    final db = await BookshelfDatabase.instance();
    final placeholders = List.filled(statuses.length, '?').join(', ');
    final rows = await db.query(
      'user_book',
      where: 'status IN ($placeholders)',
      whereArgs: statuses.map((s) => s.apiValue).toList(),
      orderBy: 'user_book_id DESC',
    );
    return _attachTags(db, rows);
  }

  Future<List<BookItem>> getGrid(BookStatus status) => getByStatuses([status]);

  Future<List<BookItem>> searchFinished(FinishedFilter filter) async {
    final db = await BookshelfDatabase.instance();
    final where = <String>['status = ?'];
    final args = <Object?>[BookStatus.finished.apiValue];

    if (filter.keyword.isNotEmpty) {
      where.add('(title LIKE ? OR author LIKE ? OR publisher LIKE ?)');
      final kw = '%${filter.keyword}%';
      args.addAll([kw, kw, kw]);
    }
    if (filter.category != null) {
      where.add('category = ?');
      args.add(filter.category);
    }
    if (filter.masterpieceOnly) {
      where.add('is_masterpiece = 1');
    }
    if (filter.difficulty != null) {
      where.add('difficulty = ?');
      args.add(filter.difficulty);
    }
    if (filter.tagIds.isNotEmpty) {
      final placeholders = List.filled(filter.tagIds.length, '?').join(', ');
      where.add(
        'user_book_id IN (SELECT user_book_id FROM user_book_tag WHERE tag_id IN ($placeholders))',
      );
      args.addAll(filter.tagIds);
    }

    final rows = await db.query(
      'user_book',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'finished_at DESC, user_book_id DESC',
    );
    return _attachTags(db, rows);
  }

  Future<List<String>> getDistinctCategories() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.rawQuery(
      'SELECT DISTINCT category FROM user_book WHERE status = ? AND category IS NOT NULL '
      'ORDER BY category',
      [BookStatus.finished.apiValue],
    );
    return rows.map((r) => r['category'] as String).toList();
  }

  Future<List<String>> getDistinctDifficulties() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.rawQuery(
      'SELECT DISTINCT difficulty FROM user_book WHERE status = ? AND difficulty IS NOT NULL '
      'ORDER BY difficulty',
      [BookStatus.finished.apiValue],
    );
    return rows.map((r) => r['difficulty'] as String).toList();
  }

  Future<List<BookTag>> getDistinctTags() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT t.tag_id, t.tag_name
      FROM user_book_tag t
      INNER JOIN user_book b ON b.user_book_id = t.user_book_id
      WHERE b.status = ?
      ORDER BY t.tag_name
      ''',
      [BookStatus.finished.apiValue],
    );
    return rows
        .map(
          (r) => BookTag(id: r['tag_id'] as int, name: r['tag_name'] as String),
        )
        .toList();
  }

  Future<DateTime?> getLastSyncedAt() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['last_synced_at'],
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['value'] as String);
  }

  /// 서버 전체 스냅샷으로 로컬 DB를 맞춘다: 서버에 있는 행은 upsert, 서버에
  /// 없는(로컬에만 남은) 비-dirty 행은 삭제. dirty 행은 upsert도 삭제도 하지 않는다.
  ///
  /// [requestedAt]은 이 전체 동기화 요청을 보내기 *직전* 시각(UTC)이어야 한다.
  /// 응답을 받은 뒤의 시각을 쓰면 그 사이 서버에 반영된 변경이 다음 증분
  /// 동기화의 since보다 앞서게 되어 영구히 누락될 수 있다.
  Future<void> reconcile(
    List<BookItem> serverItems,
    DateTime requestedAt,
  ) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final serverIds = serverItems.map((e) => e.userBookId).toList();

      for (final item in serverItems) {
        await _upsertItemTxn(txn, item, syncedUpdatedAt: item.updatedAt);
      }

      if (serverIds.isEmpty) {
        await txn.delete('user_book', where: 'is_dirty = 0');
      } else {
        final placeholders = List.filled(serverIds.length, '?').join(', ');
        await txn.delete(
          'user_book',
          where: 'user_book_id NOT IN ($placeholders) AND is_dirty = 0',
          whereArgs: serverIds,
        );
      }

      await txn.insert('sync_meta', {
        'key': 'last_synced_at',
        'value': requestedAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// 증분 동기화 결과를 로컬 DB에 반영한다: upserted 항목은 upsert, deletedUserBookIds는
  /// 삭제. 둘 다 dirty 행은 건드리지 않는다([reconcile]과 동일한 보호 정책).
  /// 반영이 전부 끝난 트랜잭션 안에서만 다음 since 기준값(syncedAt)을 갱신하므로,
  /// 도중에 실패하면 기준값은 그대로 남아 다음 시도에서 같은 구간을 다시 받는다.
  Future<void> applyChanges({
    required List<BookItem> upserted,
    required List<int> deletedUserBookIds,
    required DateTime syncedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      for (final item in upserted) {
        await _upsertItemTxn(txn, item, syncedUpdatedAt: item.updatedAt);
      }

      if (deletedUserBookIds.isNotEmpty) {
        final placeholders = List.filled(
          deletedUserBookIds.length,
          '?',
        ).join(', ');
        await txn.delete(
          'user_book',
          where: 'user_book_id IN ($placeholders) AND is_dirty = 0',
          whereArgs: deletedUserBookIds,
        );
      }

      await txn.insert('sync_meta', {
        'key': 'last_synced_at',
        'value': syncedAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// 책 기록 화면에서 서버 PATCH가 성공한 뒤 그 결과 한 건만 로컬에 반영할 때
  /// 쓴다. [reconcile]/[applyChanges]와 동일하게 dirty 행은 덮어쓰지 않고,
  /// `sync_meta.last_synced_at`은 건드리지 않는다(다음 증분 동기화가 이
  /// 행을 다시 upsert하는 것은 무해하다).
  ///
  /// [syncedUpdatedAt]은 응답에 실제 서버 `updated_at`이 함께 내려오는
  /// 호출(책 정보 PATCH)만 넘긴다 — 태그 추가/삭제처럼 클라이언트 시각으로
  /// [item.updatedAt]을 채운 호출은 생략해 기존 충돌 검사 기준값을
  /// 그대로 보존해야 한다(그러지 않으면 다음 record PATCH의 충돌 검사가
  /// 실제로 존재하지 않는 서버 시각을 기준으로 잘못 비교된다).
  Future<void> upsertOne(BookItem item, {DateTime? syncedUpdatedAt}) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction(
      (txn) => _upsertItemTxn(txn, item, syncedUpdatedAt: syncedUpdatedAt),
    );
  }

  /// 서재에서 책을 삭제(DELETE API 성공)한 뒤 로컬 행을 제거한다.
  Future<void> deleteOne(int userBookId) async {
    final db = await BookshelfDatabase.instance();
    await db.delete(
      'user_book',
      where: 'user_book_id = ?',
      whereArgs: [userBookId],
    );
  }

  /// 책 기록 화면의 필드 수정을 로컬에 즉시 반영하고 `is_dirty = 1`로
  /// 표시한다. [_upsertItemTxn]과 달리 이미 dirty인 행도 덮어쓴다(오프라인
  /// 중 같은 책을 연달아 수정하면 최신 값으로 계속 갱신되어야 하므로).
  /// `synced_updated_at`(서버 충돌 검사 기준값)은 항상 기존 값을 그대로
  /// 유지한다 — 이 값은 서버 GET 응답으로만 갱신되어야 하며, 연속된 로컬
  /// 편집마다 새로 잡으면 첫 오프라인 편집 이전의 서버 상태를 기준으로 한
  /// 충돌 검사가 불가능해진다.
  Future<void> applyLocalEdit(BookItem item) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final syncedUpdatedAt = await _readSyncedUpdatedAt(txn, item.userBookId);
      await txn.insert(
        'user_book',
        {
          ..._bookItemToRow(item),
          'is_dirty': 1,
          'synced_updated_at': syncedUpdatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _writeTagsTxn(txn, item);
    });
  }

  /// dirty 행의 서버 push가 성공한 뒤 그 응답으로 확정 반영한다. dirty
  /// 여부와 무관하게 덮어쓴다(이 호출 자체가 dirty를 해제하는 동작이므로
  /// [_upsertItemTxn]의 "dirty면 건드리지 않음" 보호를 적용하면 안 된다).
  /// `synced_updated_at`은 [item.updatedAt](PATCH 응답의 실제 서버
  /// `updated_at`, api-doc 기준)으로 갱신한다 — 다음 push가 이 값을 충돌
  /// 검사 기준으로 즉시 쓸 수 있어, 다음 동기화(GET)를 기다릴 필요가 없다.
  Future<void> confirmPush(BookItem item) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await txn.insert(
        'user_book',
        {
          ..._bookItemToRow(item),
          'is_dirty': 0,
          'synced_updated_at': item.updatedAt.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _writeTagsTxn(txn, item);
    });
  }

  /// 서버 push가 409(다른 곳에서 이미 수정됨)로 거부됐을 때 호출한다. 이
  /// 행의 로컬 편집을 서버가 거부했으므로 dirty를 해제해 다음 동기화가
  /// 다시 덮어쓸 수 있게 하고, `sync_meta.last_synced_at`도 함께 지워
  /// 다음 [BookshelfRepository.sync] 호출이 증분이 아닌 전체 동기화로
  /// 이 행(과 그 사이 놓쳤을 수 있는 다른 변경)을 다시 받아오게 한다 —
  /// 이미 지난 since 이후로 넘어간 증분 동기화는 이 행을 다시 내려주지
  /// 않을 수 있다(단건 조회 API가 없어 전체 동기화가 유일한 복구 수단).
  Future<void> resolveConflict(int userBookId) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await txn.update(
        'user_book',
        {'is_dirty': 0, 'synced_updated_at': null},
        where: 'user_book_id = ?',
        whereArgs: [userBookId],
      );
      await txn.delete('sync_meta', where: 'key = ?', whereArgs: [
        'last_synced_at',
      ]);
    });
  }

  /// 아직 서버에 반영되지 못한(is_dirty = 1) 행 전체를 push 기준값과 함께
  /// 반환한다. `BookshelfRepository.sync()`가 매 동기화 전에 일괄 재시도할
  /// 때 쓴다.
  Future<List<(BookItem, DateTime?)>> getDirtyRecords() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query('user_book', where: 'is_dirty = 1');
    if (rows.isEmpty) return const [];
    final items = await _attachTags(db, rows);
    final baselineById = {
      for (final row in rows)
        row['user_book_id'] as int: row['synced_updated_at'] as String?,
    };
    return items
        .map(
          (item) => (
            item,
            DateTime.tryParse(baselineById[item.userBookId] ?? ''),
          ),
        )
        .toList();
  }

  /// 특정 책이 dirty(is_dirty = 1)면 그 행과 push 기준값을 반환하고, 아니면
  /// (이미 push가 끝났거나 애초에 편집이 없었으면) null을 반환한다. 책 기록
  /// 화면이 편집 직후 시도하는 단건 즉시 push가 쓴다.
  Future<(BookItem, DateTime?)?> getDirtyRecord(int userBookId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'user_book',
      where: 'user_book_id = ? AND is_dirty = 1',
      whereArgs: [userBookId],
    );
    if (rows.isEmpty) return null;
    final items = await _attachTags(db, rows);
    final baseUpdatedAt = DateTime.tryParse(
      rows.first['synced_updated_at'] as String? ?? '',
    );
    return (items.first, baseUpdatedAt);
  }

  /// push는 성공했지만 그 사이 새 로컬 편집이 쌓여 필드 값은 덮어쓸 수 없을
  /// 때, 충돌 검사 기준값만 이번 push로 서버가 확인해 준 최신 updated_at으로
  /// 갱신한다. `is_dirty`와 다른 컬럼은 그대로 둔다 — 새 편집은 여전히 push가
  /// 필요하므로.
  Future<void> refreshSyncedUpdatedAt(int userBookId, DateTime updatedAt) async {
    final db = await BookshelfDatabase.instance();
    await db.update(
      'user_book',
      {'synced_updated_at': updatedAt.toUtc().toIso8601String()},
      where: 'user_book_id = ?',
      whereArgs: [userBookId],
    );
  }

  Future<String?> _readSyncedUpdatedAt(Transaction txn, int userBookId) async {
    final existing = await txn.query(
      'user_book',
      columns: ['synced_updated_at'],
      where: 'user_book_id = ?',
      whereArgs: [userBookId],
    );
    if (existing.isEmpty) return null;
    return existing.first['synced_updated_at'] as String?;
  }

  Future<void> _upsertItemTxn(
    Transaction txn,
    BookItem item, {
    DateTime? syncedUpdatedAt,
  }) async {
    final existing = await txn.query(
      'user_book',
      columns: ['is_dirty', 'synced_updated_at'],
      where: 'user_book_id = ?',
      whereArgs: [item.userBookId],
    );
    final isDirtyLocally =
        existing.isNotEmpty && existing.first['is_dirty'] == 1;
    if (isDirtyLocally) return;

    // 호출부가 [syncedUpdatedAt]을 채워 보낼 때만(서버 GET 응답 —
    // reconcile/applyChanges, 또는 실제 서버 updated_at을 응답으로 받은
    // upsertOne 호출 — 책 정보 PATCH) 실제 서버 updated_at으로 갱신한다.
    // 그 외(태그 추가/삭제처럼 응답에 updated_at이 없어 클라이언트 시각으로
    // item.updatedAt을 채운 호출)는 기존 값을 그대로 이어간다 — 클라이언트
    // 시각을 대신 채우면 다음 push의 충돌 검사가 실제로 존재하지 않는 서버
    // 시각을 기준으로 비교돼 잘못된 409를 유발할 수 있다.
    final resolvedSyncedUpdatedAt =
        syncedUpdatedAt?.toUtc().toIso8601String() ??
        (existing.isEmpty ? null : existing.first['synced_updated_at'] as String?);

    await txn.insert(
      'user_book',
      {..._bookItemToRow(item), 'synced_updated_at': resolvedSyncedUpdatedAt},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _writeTagsTxn(txn, item);
  }

  Future<void> _writeTagsTxn(Transaction txn, BookItem item) async {
    await txn.delete(
      'user_book_tag',
      where: 'user_book_id = ?',
      whereArgs: [item.userBookId],
    );
    for (final tag in item.tags) {
      await txn.insert('user_book_tag', {
        'user_book_id': item.userBookId,
        'tag_id': tag.id,
        'tag_name': tag.name,
      });
    }
  }

  Future<List<BookItem>> _attachTags(
    Database db,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r['user_book_id'] as int).toList();
    final placeholders = List.filled(ids.length, '?').join(', ');
    final tagRows = await db.rawQuery(
      'SELECT * FROM user_book_tag WHERE user_book_id IN ($placeholders) ORDER BY tag_name',
      ids,
    );
    final tagsByBook = <int, List<BookTag>>{};
    for (final t in tagRows) {
      final bookId = t['user_book_id'] as int;
      (tagsByBook[bookId] ??= []).add(
        BookTag(id: t['tag_id'] as int, name: t['tag_name'] as String),
      );
    }
    return rows
        .map(
          (r) => _rowToBookItem(
            r,
            tagsByBook[r['user_book_id'] as int] ?? const [],
          ),
        )
        .toList();
  }

  Map<String, Object?> _bookItemToRow(BookItem item) {
    return {
      'user_book_id': item.userBookId,
      'book_id': item.bookId,
      'isbn13': item.isbn13,
      'title': item.title,
      'author': item.author,
      'publisher': item.publisher,
      'total_pages': item.totalPages,
      'cover_image_url': item.coverImageUrl,
      'display_category_id': item.displayCategoryId,
      'category': item.category,
      'status': item.status.apiValue,
      'current_page': item.currentPage,
      'my_rating': item.myRating,
      'short_review': item.shortReview,
      'is_masterpiece': item.isMasterpiece ? 1 : 0,
      'source_type': item.sourceType,
      'reread_count': item.rereadCount,
      'difficulty': item.difficulty,
      'started_at': _formatDate(item.startedAt),
      'finished_at': _formatDate(item.finishedAt),
      'library_id': item.libraryId,
      'library_due_at': _formatDate(item.libraryDueAt),
      'platform_name': item.platformName,
      'discovery_source': item.discoverySource,
      'created_at': item.createdAt.toIso8601String(),
      'updated_at': item.updatedAt.toIso8601String(),
      'is_dirty': 0,
    };
  }

  BookItem _rowToBookItem(Map<String, dynamic> row, List<BookTag> tags) {
    return BookItem(
      userBookId: row['user_book_id'] as int,
      bookId: row['book_id'] as int?,
      isbn13: row['isbn13'] as String?,
      title: row['title'] as String,
      author: row['author'] as String?,
      publisher: row['publisher'] as String?,
      totalPages: row['total_pages'] as int?,
      coverImageUrl: row['cover_image_url'] as String?,
      displayCategoryId: row['display_category_id'] as int?,
      category: row['category'] as String?,
      status: BookStatus.fromApiValue(row['status'] as String),
      currentPage: row['current_page'] as int,
      myRating: (row['my_rating'] as num?)?.toDouble(),
      shortReview: row['short_review'] as String?,
      isMasterpiece: (row['is_masterpiece'] as int) == 1,
      sourceType: row['source_type'] as String?,
      rereadCount: row['reread_count'] as int,
      difficulty: row['difficulty'] as String?,
      startedAt: _parseDate(row['started_at'] as String?),
      finishedAt: _parseDate(row['finished_at'] as String?),
      libraryId: row['library_id'] as int?,
      libraryDueAt: _parseDate(row['library_due_at'] as String?),
      platformName: row['platform_name'] as String?,
      discoverySource: row['discovery_source'] as String?,
      tags: tags,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  String? _formatDate(DateTime? date) =>
      date?.toIso8601String().substring(0, 10);

  DateTime? _parseDate(String? value) =>
      value == null ? null : DateTime.parse(value);
}
