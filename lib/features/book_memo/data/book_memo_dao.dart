import 'package:sqflite/sqflite.dart';

import '../../bookshelf/data/bookshelf_database.dart';
import '../models/book_memo.dart';

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
        orderBy: 'created_at DESC, sort_order DESC, id DESC',
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
      userBookId: row['user_book_id'] as int,
      title: row['title'] as String?,
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
      memoId: row['memo_id'] as int,
      type: BookMemoItemType.fromDb(row['item_type'] as String),
      startPage: row['start_page'] as int?,
      endPage: row['end_page'] as int?,
      content: row['content'] as String?,
      imageUrl: row['image_url'] as String?,
      isImportant: (row['is_important'] as int) == 1,
      sortOrder: row['sort_order'] as int,
      createdAt: createdAt,
      updatedAt: updatedAt == null ? createdAt : DateTime.parse(updatedAt),
      isDirty: (row['is_dirty'] as int) == 1,
    );
  }
}
