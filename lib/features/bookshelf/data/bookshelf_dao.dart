import 'package:sqflite/sqflite.dart';

import '../models/book_item.dart';
import '../models/book_status.dart';
import '../models/book_tag.dart';
import '../models/finished_filter.dart';
import 'bookshelf_database.dart';

/// 책장 로컬 DB 쿼리/쓰기 전담.
///
/// `is_dirty = 1`인 로컬 행은 [reconcile](전체 동기화)/[applyChanges](증분
/// 동기화) 모두 서버 데이터로 덮어쓰거나 삭제하지 않는다. 이번 작업 범위에는
/// 책 수정 기능이 없어 dirty 행이 실제로 생기지는 않지만, 향후 책 수정
/// 기능이 dirty를 표시하기 시작해도 동기화가 로컬 편집을 지우지 않도록
/// 순서를 미리 맞춰 둔다.
class BookshelfDao {
  const BookshelfDao();

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
    return rows.map((r) => BookTag(id: r['tag_id'] as int, name: r['tag_name'] as String)).toList();
  }

  Future<DateTime?> getLastSyncedAt() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query('sync_meta', where: 'key = ?', whereArgs: ['last_synced_at']);
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['value'] as String);
  }

  /// 서버 전체 스냅샷으로 로컬 DB를 맞춘다: 서버에 있는 행은 upsert, 서버에
  /// 없는(로컬에만 남은) 비-dirty 행은 삭제. dirty 행은 upsert도 삭제도 하지 않는다.
  ///
  /// [requestedAt]은 이 전체 동기화 요청을 보내기 *직전* 시각(UTC)이어야 한다.
  /// 응답을 받은 뒤의 시각을 쓰면 그 사이 서버에 반영된 변경이 다음 증분
  /// 동기화의 since보다 앞서게 되어 영구히 누락될 수 있다.
  Future<void> reconcile(List<BookItem> serverItems, DateTime requestedAt) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final serverIds = serverItems.map((e) => e.userBookId).toList();

      for (final item in serverItems) {
        final existing = await txn.query(
          'user_book',
          columns: ['is_dirty'],
          where: 'user_book_id = ?',
          whereArgs: [item.userBookId],
        );
        final isDirtyLocally = existing.isNotEmpty && existing.first['is_dirty'] == 1;
        if (isDirtyLocally) continue;

        await txn.insert(
          'user_book',
          _bookItemToRow(item),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await txn.delete('user_book_tag', where: 'user_book_id = ?', whereArgs: [item.userBookId]);
        for (final tag in item.tags) {
          await txn.insert('user_book_tag', {
            'user_book_id': item.userBookId,
            'tag_id': tag.id,
            'tag_name': tag.name,
          });
        }
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
        final existing = await txn.query(
          'user_book',
          columns: ['is_dirty'],
          where: 'user_book_id = ?',
          whereArgs: [item.userBookId],
        );
        final isDirtyLocally = existing.isNotEmpty && existing.first['is_dirty'] == 1;
        if (isDirtyLocally) continue;

        await txn.insert(
          'user_book',
          _bookItemToRow(item),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await txn.delete('user_book_tag', where: 'user_book_id = ?', whereArgs: [item.userBookId]);
        for (final tag in item.tags) {
          await txn.insert('user_book_tag', {
            'user_book_id': item.userBookId,
            'tag_id': tag.id,
            'tag_name': tag.name,
          });
        }
      }

      if (deletedUserBookIds.isNotEmpty) {
        final placeholders = List.filled(deletedUserBookIds.length, '?').join(', ');
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

  Future<List<BookItem>> _attachTags(Database db, List<Map<String, dynamic>> rows) async {
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
        .map((r) => _rowToBookItem(r, tagsByBook[r['user_book_id'] as int] ?? const []))
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

  String? _formatDate(DateTime? date) => date?.toIso8601String().substring(0, 10);

  DateTime? _parseDate(String? value) => value == null ? null : DateTime.parse(value);
}
