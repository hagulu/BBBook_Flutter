import 'package:sqflite/sqflite.dart';

import '../models/book_category.dart';
import 'bookshelf_database.dart';

/// `book_category` 로컬 캐시 DAO. 계정과 무관한 전역 마스터 데이터라
/// [BookshelfDatabase.clearAll]의 로그아웃 초기화 대상에서 제외되어 있다.
class BookCategoryDao {
  const BookCategoryDao();

  static const _refreshedAtKey = 'category_refreshed_at';

  Future<List<BookCategory>> getAll() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query('book_category', orderBy: 'sort_order ASC');
    return rows.map(_rowToCategory).toList();
  }

  /// 마지막으로 [replaceAll]이 실행된 시각. 없으면(최초 실행 전) null.
  Future<DateTime?> getLastRefreshedAt() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [_refreshedAtKey],
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['value'] as String);
  }

  /// 서버 응답(이미 sort_order 오름차순)을 그대로 로컬 캐시로 교체하고,
  /// 갱신 시각을 `sync_meta`에 남긴다
  /// ([BookshelfRepository.refreshCategoriesIfStale]가 이 값으로 재조회
  /// 주기를 판단한다).
  Future<void> replaceAll(List<BookCategory> categories) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await txn.delete('book_category');
      for (var i = 0; i < categories.length; i++) {
        final category = categories[i];
        await txn.insert('book_category', {
          'id': category.id,
          'code': category.code,
          'name': category.name,
          'color_hex': category.colorHex,
          'sort_order': i,
        });
      }
      await txn.insert('sync_meta', {
        'key': _refreshedAtKey,
        'value': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  BookCategory _rowToCategory(Map<String, Object?> row) {
    return BookCategory(
      id: row['id'] as int,
      code: row['code'] as String,
      name: row['name'] as String,
      colorHex: row['color_hex'] as String,
    );
  }
}
