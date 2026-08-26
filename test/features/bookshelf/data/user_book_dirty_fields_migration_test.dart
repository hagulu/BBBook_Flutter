import 'dart:io';

import 'package:bbbook/features/bookshelf/data/bookshelf_dao.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/bookshelf/models/record_patch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v15 → v16 마이그레이션 검증.
///
/// v16은 로컬 우선 편집이 바꾼 필드를 기록하는 `user_book.dirty_fields`를
/// 추가한다. 이전 버전에서 이미 쌓여 있던 dirty 행은 무엇을 바꿨는지 알 수
/// 없으므로 NULL로 남고, push는 예전과 같이 "값이 있는 필드만" 보내야 한다
/// — 그 행에 명시적 null(삭제)을 실으면 사용자가 지운 적 없는 서버 값까지
/// 지워진다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v15의 dirty 행은 컬럼 추가 후에도 삭제를 보내지 않는다', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final databaseDirectory = await Directory.systemTemp.createTemp(
      'bookshelf_dirty_fields_migration',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    final databasePath = path.join(databaseDirectory.path, 'bookshelf.db');
    await databaseFactory.deleteDatabase(databasePath);

    // v15 스키마의 user_book/user_book_tag만 만들어 실제 업그레이드 경로를
    // 태운다(`dirty_fields` 컬럼이 없는 상태).
    final legacy = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 15,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE user_book (
              user_book_id INTEGER PRIMARY KEY,
              server_id INTEGER,
              book_id INTEGER,
              isbn13 TEXT,
              title TEXT NOT NULL,
              author TEXT,
              publisher TEXT,
              total_pages INTEGER,
              cover_image_url TEXT,
              display_category_id INTEGER,
              category TEXT,
              status TEXT NOT NULL,
              current_page INTEGER NOT NULL DEFAULT 0,
              my_rating REAL,
              short_review TEXT,
              is_masterpiece INTEGER NOT NULL DEFAULT 0,
              source_type TEXT,
              reread_count INTEGER NOT NULL DEFAULT 0,
              difficulty TEXT,
              started_at TEXT,
              finished_at TEXT,
              library_id INTEGER,
              library_due_at TEXT,
              platform_name TEXT,
              discovery_source TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              is_dirty INTEGER NOT NULL DEFAULT 0,
              synced_updated_at TEXT,
              client_request_id TEXT,
              create_thumbnail_path TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE user_book_tag (
              user_book_id INTEGER NOT NULL,
              tag_id INTEGER NOT NULL,
              tag_name TEXT NOT NULL,
              PRIMARY KEY (user_book_id, tag_id)
            )
          ''');
          await db.insert('user_book', {
            'user_book_id': 1,
            'server_id': 1,
            'title': '책',
            'status': 'READING',
            'current_page': 30,
            'my_rating': null,
            'short_review': '좋았다',
            'is_masterpiece': 0,
            'reread_count': 0,
            'platform_name': null,
            'created_at': '2026-08-20T00:00:00.000Z',
            'updated_at': '2026-08-25T00:00:00.000Z',
            'is_dirty': 1,
            'synced_updated_at': '2026-08-20T00:00:00.000Z',
          });
        },
      ),
    );
    await legacy.close();

    // 실제 앱과 같은 경로로 다시 열어 v16 업그레이드를 태운다.
    const dao = BookshelfDao();
    final dirty = await dao.getDirtyRecord(1);

    expect(dirty, isNotNull);
    expect(dirty!.changedFields, isNull, reason: '무엇을 바꿨는지 알 수 없는 레거시 행');
    expect(dirty.baseUpdatedAt, DateTime.utc(2026, 8, 20));

    final body = RecordPatch.fromSnapshot(
      dirty.item,
      changedFields: dirty.changedFields,
    ).toJson();

    // 값이 없는 필드에 명시적 null(삭제)을 실으면 안 된다.
    expect(body.containsKey('myRating'), isFalse);
    expect(body.containsKey('platformName'), isFalse);
    expect(body.containsKey('startedAt'), isFalse);
    // 값이 있는 필드와 삭제 불가 필드는 예전처럼 그대로 보낸다.
    expect(body['shortReview'], '좋았다');
    expect(body['status'], 'READING');
    expect(body['currentPage'], 30);

    // 컬럼이 실제로 추가돼 이후 편집은 정상적으로 추적된다.
    final db = await BookshelfDatabase.instance();
    final columns = await db.rawQuery('PRAGMA table_info(user_book)');
    expect(columns.map((row) => row['name']), contains('dirty_fields'));
  });
}
