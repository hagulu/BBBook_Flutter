import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../bookshelf/data/bookshelf_database.dart';
import '../models/auth_user.dart';
import '../models/standalone_session.dart';

/// 기록과 같은 DB에 소유자를 보관한다. 토큰은 별도 secure storage에 둔다.
class LocalAuthStore {
  const LocalAuthStore();

  static const _userKey = 'local_auth_user';

  /// 로그인 없이 사용하기로 진입했는지. 앱을 다시 켜도 그 상태로 돌아가기
  /// 위해 기록 DB에 남긴다. 서버 저장 모드 로그아웃이 실행하는
  /// [BookshelfDatabase.clearAll]이 `sync_meta`를 비우며 이 표시도 지운다.
  static const _standaloneSessionKey = 'standalone_session_active';

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
      whereArgs: [_userKey],
    );
    if (rows.isNotEmpty) {
      return AuthUser.fromJson(
        jsonDecode(rows.single['value'] as String) as Map<String, dynamic>,
      );
    }

    // 업데이트 이전 설치도 네트워크 없이 복원한다. 소유자가 하나로
    // 확인되는 경우에만 기존 메타데이터를 사용한다(빈 책장도 포함).
    // 계정 없는 사용자의 sentinel은 서버 계정이 아니므로 후보에서 제외한다 — 포함하면
    // 그 기록만 있는 기기가 존재하지 않는 계정으로 복원된다.
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
    owners.remove(standaloneOwnerUserId);
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
      'key': _userKey,
      'value': jsonEncode({
        'id': user.id,
        'nickname': user.nickname,
        'profileImageUrl': user.profileImageUrl,
        'isFinishedBooksPublic': user.isFinishedBooksPublic,
        'isSanctioned': user.isSanctioned,
        'sanction': user.sanction == null
            ? null
            : {
                'reason': user.sanction!.reason,
                'reasonLabel': user.sanction!.reasonLabel,
                'isPermanent': user.sanction!.isPermanent,
                'endsAt': user.sanction!.endsAt?.toIso8601String(),
              },
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 로컬 기록을 남긴 채 계정만 떼어낼 때 호출한다(로컬 저장 모드 로그아웃).
  /// 이 행이 남아 있으면 다음 실행에서 로그인 없이 그 계정으로 복원된다.
  Future<void> clearUser() async =>
      clearUserIn(await BookshelfDatabase.instance());

  /// 소유자 변경과 한 트랜잭션으로 묶을 때 쓴다([rekeyRecordOwnerIn] 참고).
  Future<void> clearUserIn(DatabaseExecutor txn) =>
      txn.delete('sync_meta', where: 'key = ?', whereArgs: [_userKey]);

  Future<bool> isStandaloneSessionActive() async {
    final db = await BookshelfDatabase.instance();
    return (await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [_standaloneSessionKey],
    )).isNotEmpty;
  }

  Future<void> startStandaloneSession() async =>
      startStandaloneSessionIn(await BookshelfDatabase.instance());

  /// 소유자 변경과 한 트랜잭션으로 묶을 때 쓴다([rekeyRecordOwnerIn] 참고).
  Future<void> startStandaloneSessionIn(DatabaseExecutor txn) => txn.insert(
    'sync_meta',
    {'key': _standaloneSessionKey, 'value': '1'},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> endStandaloneSession() async =>
      endStandaloneSessionIn(await BookshelfDatabase.instance());

  /// 소유자 변경과 한 트랜잭션으로 묶을 때 쓴다([rekeyRecordOwnerIn] 참고).
  Future<void> endStandaloneSessionIn(DatabaseExecutor txn) => txn.delete(
    'sync_meta',
    where: 'key = ?',
    whereArgs: [_standaloneSessionKey],
  );

  /// 로컬 기록의 소유자를 통째로 바꾼다(계정 없이 쓰던 기록 → 로그인 계정, 또는 로컬 저장
  /// 모드 로그아웃 시 로그인 계정 → 계정 없음). 기록을 복사하지 않고 소유자
  /// 컬럼만 갈아 끼우므로 노트·독후감·사진 파일이 그대로 이어진다.
  ///
  /// `owner_user_id`를 가진 테이블은 `book_note`/`book_reflection` 둘뿐이다
  /// (책·태그·메모는 부모를 따라간다 — `bookshelf_database.dart` 스키마 참고).
  Future<void> rekeyRecordOwner({required int from, required int to}) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) => rekeyRecordOwnerIn(txn, from: from, to: to));
  }

  /// 소유자 변경은 저장 모드(`storage_mode`)·세션 표시(`sync_meta`) 갱신과
  /// **반드시 한 트랜잭션**이어야 한다 — 일부만 반영된 채 앱이 종료되면
  /// 조회 기준(소유자)과 실제 행이 어긋나 노트·독후감이 통째로 보이지 않는다.
  /// 그래서 호출부는 [StorageModeStore]의 `alongside` 인자로 이 메서드를
  /// 넘겨 함께 커밋한다.
  Future<void> rekeyRecordOwnerIn(
    DatabaseExecutor txn, {
    required int from,
    required int to,
  }) async {
    if (from == to) return;
    for (final table in ['book_note', 'book_reflection']) {
      await txn.update(
        table,
        {'owner_user_id': to},
        where: 'owner_user_id = ?',
        whereArgs: [from],
      );
    }
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
