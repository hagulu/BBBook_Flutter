import 'dart:io';

import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v11 → v12 마이그레이션 검증.
///
/// v11까지는 업로드 전 사진의 로컬 경로를 `image_url`에 그대로 담아 뒀다.
/// v12는 그 값을 `local_image_path`로 옮기고 `image_url`을 서버 값 전용으로
/// 되돌린다 — 옮기지 못하면 아직 push되지 않은 사진 메모가 올릴 파일을
/// 영영 찾지 못한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v11의 image_url 로컬 경로가 local_image_path로 이관된다', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 다른 테스트 파일과 같은 `bookshelf.db` 경로를 공유하면(테스트 파일은
    // 병렬 실행된다) 여기서 만드는 구버전 스키마가 서로를 덮어쓴다.
    final databaseDirectory = await Directory.systemTemp.createTemp(
      'bookshelf_migration',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    final databasePath = path.join(databaseDirectory.path, 'bookshelf.db');
    await databaseFactory.deleteDatabase(databasePath);

    // v11 스키마의 노트/메모 테이블만 만들어 실제 업그레이드 경로를 태운다.
    final legacy = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE book_note (
              id INTEGER PRIMARY KEY,
              server_id INTEGER,
              owner_user_id INTEGER NOT NULL,
              user_book_id INTEGER NOT NULL,
              title TEXT,
              deleted_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              is_dirty INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE book_note_memo (
              id INTEGER PRIMARY KEY,
              server_id INTEGER,
              client_request_id TEXT,
              note_id INTEGER NOT NULL,
              memo_type TEXT NOT NULL,
              start_page INTEGER,
              end_page INTEGER,
              content TEXT,
              image_url TEXT,
              is_important INTEGER NOT NULL DEFAULT 0,
              sort_order INTEGER NOT NULL DEFAULT 0,
              deleted_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT,
              is_dirty INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      ),
    );
    const now = '2026-08-23T00:00:00.000Z';
    await legacy.insert('book_note', {
      'id': 1,
      'server_id': 1,
      'owner_user_id': 7,
      'user_book_id': 20,
      'created_at': now,
      'updated_at': now,
      'is_dirty': 0,
    });
    await legacy.insert('book_note_memo', {
      'id': 10,
      'note_id': 1,
      'memo_type': 'PHOTO',
      'image_url': '/var/app/Support/memo_images/memo_1.jpg',
      'created_at': now,
      'updated_at': now,
      'is_dirty': 1,
    });
    await legacy.insert('book_note_memo', {
      'id': 11,
      'note_id': 1,
      'memo_type': 'PHOTO',
      'image_url': 'https://cdn.example.com/notes/1/photo.jpg',
      'created_at': now,
      'updated_at': now,
      'is_dirty': 0,
    });
    await legacy.close();

    final db = await BookshelfDatabase.instance();
    final rows = await db.query('book_note_memo', orderBy: 'id ASC');

    // 업로드 대기 중이던 로컬 사진: 새 컬럼으로 옮기고 image_url은 비운다.
    expect(
      rows.first['local_image_path'],
      '/var/app/Support/memo_images/memo_1.jpg',
    );
    expect(rows.first['image_url'], isNull);
    // 이미 서버에 있는 사진: 그대로 두고 로컬 사본은 아직 없다.
    expect(rows.last['image_url'], 'https://cdn.example.com/notes/1/photo.jpg');
    expect(rows.last['local_image_path'], isNull);
  });
}
