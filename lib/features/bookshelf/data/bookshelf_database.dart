import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// 책장 로컬 DB(sqflite) 스키마.
///
/// `user_book.is_dirty`는 책 기록 화면의 필드 수정이 "로컬 우선 반영 → dirty
/// 표시 → 서버로 조용히 push → 실패 시 dirty 유지, 다음 동기화 때 일괄 재시도"
/// 순서로 동작하게 한다(`BookshelfDao.applyLocalEdit`/`confirmPush`,
/// `BookshelfRepository.sync`). `synced_updated_at`은 "마지막으로 확인한 서버
/// updated_at" 값으로, 로컬 편집을 서버로 push할 때 `updatedAt` 충돌 검사
/// 파라미터로 사용한다. 서버 GET 응답(전체/증분 동기화)뿐 아니라 PATCH 응답
/// (api-doc 기준 `updatedAt` 포함)에서도 갱신된다 — push가 성공하면 그
/// 응답의 실제 서버 값으로 바로 다음 push의 기준값을 채운다.
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
      version: 3,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createBookCategoryTable(db);
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE user_book ADD COLUMN synced_updated_at TEXT',
          );
          // 기존 행의 `updated_at` 컬럼은 서버 GET 응답으로 채워졌을 수도,
          // (이번 업데이트 이전) 책 정보 PATCH·태그 추가/삭제 성공 응답을
          // 클라이언트 시각으로 보강해 채운 것일 수도 있어 어느 쪽인지 구분할
          // 수 없다 — 잘못 이관하면 실제로는 다르지 않은데 409가 나거나,
          // 반대로 진짜 충돌을 놓칠 수 있다. `synced_updated_at`을 비워 둔
          // 채(새 컬럼 기본값 NULL) `last_synced_at`도 지워, 다음
          // `BookshelfRepository.sync()`가 무조건 전체 동기화로 모든 행의
          // 충돌 검사 기준값을 서버 응답으로 새로 채우게 한다.
          await db.delete(
            'sync_meta',
            where: 'key = ?',
            whereArgs: ['last_synced_at'],
          );
        }
      },
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
            is_dirty INTEGER NOT NULL DEFAULT 0,
            synced_updated_at TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_user_book_status ON user_book(status)',
        );
        await db.execute(
          'CREATE INDEX idx_user_book_finished_at ON user_book(finished_at)',
        );
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
        await _createBookCategoryTable(db);
      },
    );
  }

  /// `sort_order`는 서버 응답 배열의 위치를 그대로 저장한다(API가 `sort_order`
  /// 값 자체는 내려주지 않고 이미 정렬된 배열만 반환하므로).
  static Future<void> _createBookCategoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_category (
        id INTEGER PRIMARY KEY,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        color_hex TEXT NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');
  }

  /// 로그아웃 시 이전 계정 데이터가 다음 로그인 사용자에게 노출되지 않도록 전부 비운다.
  /// `book_category`는 계정과 무관한 전역 마스터 데이터(인증 불필요 API 응답)라
  /// 로그아웃해도 지우지 않는다.
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
