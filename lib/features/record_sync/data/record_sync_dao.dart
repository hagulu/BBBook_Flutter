import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../bookshelf/data/bookshelf_dao.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../models/record_sync_payload.dart';

typedef RecordSaveProgress = void Function(int saved, int total);

class RecordSyncDao {
  const RecordSyncDao([this._bookshelfDao = const BookshelfDao()]);

  final BookshelfDao _bookshelfDao;

  String _completionKey(int userId) =>
      'initial_flat_records_synced_user_$userId';

  List<String> _legacyCompletionKeys(int userId) => [
    'initial_records_synced_user_$userId',
    'initial_records_with_books_synced_user_$userId',
  ];

  Future<bool> isInitialSyncCompleted(int userId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'sync_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_completionKey(userId)],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 기존 clean 기록 교체와 완료 표시를 하나의 트랜잭션으로 처리한다.
  /// 실패하면 모든 insert/delete와 완료 메타가 함께 롤백된다.
  Future<void> replaceInitialRecords({
    required int userId,
    required int expectedSessionGeneration,
    required DateTime requestedAt,
    required RecordSyncPayload payload,
    required RecordSaveProgress onProgress,
  }) async {
    final db = await BookshelfDatabase.instance();
    final total = payload.totalItemCount;
    var saved = 0;

    await db.transaction((txn) async {
      if (BookshelfDatabase.sessionGeneration != expectedSessionGeneration) {
        throw const RecordSyncSessionChanged();
      }

      await _bookshelfDao.reconcileInTransaction(
        txn,
        payload.books,
        requestedAt,
        onItemSaved: () => onProgress(++saved, total),
      );

      await txn.delete(
        'book_memo_item',
        where: 'memo_id IN (SELECT id FROM book_memo WHERE owner_user_id = ?)',
        whereArgs: [userId],
      );
      await txn.delete(
        'book_memo',
        where: 'owner_user_id = ?',
        whereArgs: [userId],
      );
      await txn.delete(
        'book_reflection',
        where: 'owner_user_id = ?',
        whereArgs: [userId],
      );

      for (final memo in payload.memos) {
        await txn.insert('book_memo', {
          'id': memo.id,
          // 최초 동기화로 받은 행은 서버에 이미 존재하는 행이므로 server_id를
          // id와 동일하게 채운다 — BookMemoRepository.sync()의 dirty push가
          // "server_id == null"을 "아직 서버에 없는 로컬 전용 행"으로
          // 판별하는 기준이 되므로 비워두면 안 된다.
          'server_id': memo.id,
          'owner_user_id': userId,
          'user_book_id': memo.userBookId,
          'title': memo.title,
          'deleted_at': null,
          'created_at': _date(memo.createdAt),
          'updated_at': _date(memo.updatedAt),
          'is_dirty': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        onProgress(++saved, total);
      }

      for (final item in payload.items) {
        await txn.insert('book_memo_item', {
          'id': item.id,
          'server_id': item.id,
          'memo_id': item.memoId,
          'item_type': item.itemType,
          'start_page': item.startPage,
          'end_page': item.endPage,
          'content': item.content,
          'image_url': item.imageUrl,
          'is_important': item.isImportant ? 1 : 0,
          'sort_order': item.sortOrder,
          'deleted_at': null,
          'created_at': _date(item.createdAt),
          'updated_at': _date(item.updatedAt),
          'is_dirty': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        onProgress(++saved, total);
      }

      for (final reflection in payload.reflections) {
        await txn.insert('book_reflection', {
          'id': reflection.id,
          'owner_user_id': userId,
          'user_book_id': reflection.userBookId,
          'reflection_type': reflection.reflectionType,
          'title': reflection.title,
          'content_json': reflection.contentJson == null
              ? null
              : jsonEncode(reflection.contentJson),
          'content_text': reflection.contentText,
          'is_public': reflection.isPublic ? 1 : 0,
          'is_hidden': reflection.isHidden ? 1 : 0,
          'deleted_at': null,
          'created_at': _date(reflection.createdAt),
          'updated_at': _date(reflection.updatedAt),
          'is_dirty': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        onProgress(++saved, total);
      }

      if (BookshelfDatabase.sessionGeneration != expectedSessionGeneration) {
        throw const RecordSyncSessionChanged();
      }
      await txn.delete(
        'sync_meta',
        where: 'key IN (?, ?)',
        whereArgs: _legacyCompletionKeys(userId),
      );
      await txn.insert('sync_meta', {
        'key': _completionKey(userId),
        'value': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // 메모 동기화 기준값(BookMemoRepository.sync()가 쓰는 since)도 이번
      // 요청 시각으로 함께 시딩한다 — 그러지 않으면 최초 동기화 직후의 첫
      // 메모 sync()가 방금 다 받은 데이터를 또 전체 조회로 중복 요청한다.
      await txn.insert('sync_meta', {
        'key': 'last_synced_at_memo',
        'value': requestedAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // 독후감 동기화 기준값(BookReflectionRepository.sync()가 쓰는 since)도
      // 같은 이유로 함께 시딩한다.
      await txn.insert('sync_meta', {
        'key': 'last_synced_at_reflection',
        'value': requestedAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    if (total == 0) onProgress(0, 0);
  }

  String _date(DateTime value) => value.toUtc().toIso8601String();
}

class RecordSyncSessionChanged implements Exception {
  const RecordSyncSessionChanged();
}
