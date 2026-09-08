import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../bookshelf/data/bookshelf_database.dart';
import '../models/auth_user.dart';

/// 기록과 같은 DB에 소유자를 보관한다. 토큰은 별도 secure storage에 둔다.
class LocalAuthStore {
  const LocalAuthStore();

  Future<bool> hasLocalRecords() async {
    final db = await BookshelfDatabase.instance();
    for (final table in ['user_book', 'book_note', 'book_reflection']) {
      if ((await db.query(table, limit: 1)).isNotEmpty) return true;
    }
    return false;
  }

  Future<AuthUser?> readUser() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['local_auth_user'],
    );
    if (rows.isNotEmpty) {
      return AuthUser.fromJson(
        jsonDecode(rows.single['value'] as String) as Map<String, dynamic>,
      );
    }

    // 업데이트 이전 설치도 네트워크 없이 복원한다. 소유자가 하나로
    // 확인되는 경우에만 기존 메타데이터를 사용한다(빈 책장도 포함).
    final owners = <int>{};
    final modes = await db.query('storage_mode', columns: ['owner_user_id']);
    owners.addAll(modes.map((row) => row['owner_user_id']).whereType<int>());
    final keys = await db.query('sync_meta', columns: ['key']);
    final pattern = RegExp(
      r'^initial_(?:flat_records|records|records_with_books)_synced_user_(\d+)$',
    );
    for (final row in keys) {
      final match = pattern.firstMatch(row['key'] as String);
      if (match != null) owners.add(int.parse(match.group(1)!));
    }
    for (final table in ['book_note', 'book_reflection']) {
      final rows = await db.query(
        table,
        columns: ['owner_user_id'],
        distinct: true,
      );
      owners.addAll(rows.map((row) => row['owner_user_id']).whereType<int>());
    }
    if (owners.length != 1) return null;
    return AuthUser(
      id: owners.single,
      nickname: null,
      profileImageUrl: null,
      isFinishedBooksPublic: false,
    );
  }

  Future<void> saveUser(AuthUser user) async {
    final db = await BookshelfDatabase.instance();
    await db.insert('sync_meta', {
      'key': 'local_auth_user',
      'value': jsonEncode({
        'id': user.id,
        'nickname': user.nickname,
        'profileImageUrl': user.profileImageUrl,
        'isFinishedBooksPublic': user.isFinishedBooksPublic,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> canUseRecords(int userId) async {
    if ((await readUser())?.id != userId) return false;
    final db = await BookshelfDatabase.instance();
    final modes = await db.query(
      'storage_mode',
      where: 'mode = ? AND owner_user_id = ?',
      whereArgs: ['LOCAL', userId],
    );
    if (modes.isNotEmpty) return true;
    final completed = await db.query(
      'sync_meta',
      where: 'key IN (?, ?, ?)',
      whereArgs: [
        'initial_flat_records_synced_user_$userId',
        'initial_records_synced_user_$userId',
        'initial_records_with_books_synced_user_$userId',
      ],
    );
    if (completed.isNotEmpty) return true;
    return (await db.query(
      'user_book',
      columns: ['user_book_id'],
      limit: 1,
    )).isNotEmpty;
  }
}
