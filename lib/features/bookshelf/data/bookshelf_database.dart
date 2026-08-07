import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// 책장 로컬 DB(sqflite) 스키마.
///
/// `user_book.is_dirty`는 이번 작업 범위(책 수정 화면 없음)에서는 항상 0이지만,
/// 추후 책 수정 기능이 추가되면 "로컬 우선 반영 → dirty 표시 → 서버 push →
/// 전체 동기화" 순서의 스키마 기반을 미리 마련해 둔다.
class BookshelfDatabase {
  BookshelfDatabase._();

  static Database? _database;

  /// 로그아웃 등으로 [clearAll]이 실행될 때마다 1씩 늘어난다. 진행 중이던
  /// 동기화(`BookshelfRepository.sync`)가 이 값을 시작 시점과 비교해, 응답을
  /// 받기 전에 로그아웃이 끼어들었으면 결과를 로컬 DB에 쓰지 않고 버린다
  /// (다른 계정의 데이터가 clear 이후 되살아나는 것을 방지).
  static int sessionGeneration = 0;

  static Future<Database> instance() async {
    return _database ??= await _open();
  }

  static Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'bookshelf.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE user_book (
            user_book_id INTEGER PRIMARY KEY,
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
            is_dirty INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_user_book_status ON user_book(status)');
        await db.execute('CREATE INDEX idx_user_book_finished_at ON user_book(finished_at)');
        await db.execute('''
          CREATE TABLE user_book_tag (
            user_book_id INTEGER NOT NULL,
            tag_id INTEGER NOT NULL,
            tag_name TEXT NOT NULL,
            PRIMARY KEY (user_book_id, tag_id),
            FOREIGN KEY (user_book_id) REFERENCES user_book(user_book_id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
    );
  }

  /// 로그아웃 시 이전 계정 데이터가 다음 로그인 사용자에게 노출되지 않도록 전부 비운다.
  static Future<void> clearAll() async {
    sessionGeneration++;
    final db = await instance();
    await db.transaction((txn) async {
      await txn.delete('user_book_tag');
      await txn.delete('user_book');
      await txn.delete('sync_meta');
    });
  }
}
