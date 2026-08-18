import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
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
      version: 7,
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
        if (oldVersion < 4) {
          await _createDismissedIsbnLinkTable(db);
        }
        if (oldVersion < 5) {
          // v4의 `dismissed_isbn_link`는 `user_book`을 ON DELETE CASCADE로
          // 참조했다. 그런데 `user_book` 갱신은 거의 다 `INSERT OR REPLACE`를
          // 쓰는데(동기화 반영/로컬 우선 편집/push 확정), SQLite의 REPLACE는
          // 기존 행을 지운 뒤 다시 넣는 방식이라 그때마다 CASCADE가 걸려
          // 방금 기록한 "제외" 표시가 곧바로 지워졌다 — 사실상 기능이 동작하지
          // 않았다. FK 없는 테이블로 다시 만든다(정말 책이 삭제됐을 때의
          // 정리는 deleteOne/reconcile/applyChanges에서 직접 한다).
          await db.execute('DROP TABLE IF EXISTS dismissed_isbn_link');
          await _createDismissedIsbnLinkTable(db);
        }
        if (oldVersion < 7) {
          // v6은 이전 중첩 응답에 있던 책 snapshot을 메모/독후감에도
          // 중복 저장했다. v7부터 API의 4개 flat 배열과 같은 테이블 단위
          // 구조로 다시 만들며, 완료 키도 함께 바뀌어 전체 데이터를 재수신한다.
          await db.execute('DROP TABLE IF EXISTS book_memo_item');
          await db.execute('DROP TABLE IF EXISTS book_memo');
          await db.execute('DROP TABLE IF EXISTS book_reflection');
          await _createRecordTables(db);
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
        await _createDismissedIsbnLinkTable(db);
        await _createRecordTables(db);
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

  /// 완독 목록의 "ISBN 미연결" 일괄 연결 배너에서 사용자가 "목록에서
  /// 제외"를 선택하고 건너뛴 책을 기록한다(`bulk_isbn_link_banner.dart`).
  ///
  /// 일부러 `user_book`을 참조하는 외래 키를 걸지 않는다 — `user_book`
  /// 갱신은 거의 항상 `INSERT OR REPLACE`(동기화 반영/로컬 우선 편집/push
  /// 확정)를 쓰는데, REPLACE는 기존 행을 지운 뒤 다시 넣는 방식이라
  /// ON DELETE CASCADE를 걸면 그때마다 방금 남긴 "제외" 기록이 함께
  /// 지워진다(v5 마이그레이션 참고). 정말 책이 삭제됐을 때의 정리는
  /// [BookshelfDao.deleteOne]/[BookshelfDao.reconcile]/
  /// [BookshelfDao.applyChanges]가 직접 한다.
  static Future<void> _createDismissedIsbnLinkTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dismissed_isbn_link (
        user_book_id INTEGER PRIMARY KEY,
        dismissed_at TEXT NOT NULL
      )
    ''');
  }

  /// 전체 기록 조회(`/api/me/records`) 결과를 저장하는 로컬 테이블.
  ///
  /// `owner_user_id`는 API 응답 필드가 아닌 로컬 계정 격리용 값이다. 서버
  /// PK(`id`)와 관계 키(`user_book_id`, `memo_id`)는 원형 그대로 유지한다.
  /// 현재 전체 조회 응답에 없는 서버 삭제/수정 시각 컬럼은 향후 증분
  /// 동기화를 위해 nullable로 준비한다.
  static Future<void> _createRecordTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_memo (
        id INTEGER PRIMARY KEY,
        owner_user_id INTEGER NOT NULL,
        user_book_id INTEGER NOT NULL,
        title TEXT,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_dirty INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_book_memo_owner_user_book '
      'ON book_memo(owner_user_id, user_book_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_memo_item (
        id INTEGER PRIMARY KEY,
        memo_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        start_page INTEGER,
        end_page INTEGER,
        content TEXT,
        image_url TEXT,
        is_important INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        is_dirty INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (memo_id) REFERENCES book_memo(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_book_memo_item_memo_sort '
      'ON book_memo_item(memo_id, sort_order)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_reflection (
        id INTEGER PRIMARY KEY,
        owner_user_id INTEGER NOT NULL,
        user_book_id INTEGER NOT NULL,
        reflection_type TEXT NOT NULL,
        title TEXT,
        content_json TEXT,
        content_text TEXT,
        is_public INTEGER NOT NULL DEFAULT 0,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_dirty INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_book_reflection_owner_user_book '
      'ON book_reflection(owner_user_id, user_book_id)',
    );
  }

  /// 로그아웃 시 이전 계정 데이터가 다음 로그인 사용자에게 노출되지 않도록
  /// 책장·기록·동기화 완료 상태를 모두 비운다. `book_category`만 계정과
  /// 무관한 전역 마스터 데이터라 유지한다.
  static Future<void> clearAll() async {
    sessionGeneration++;
    final db = await instance();
    await db.transaction((txn) async {
      await txn.delete('book_memo_item');
      await txn.delete('book_memo');
      await txn.delete('book_reflection');
      await txn.delete('user_book_tag');
      await txn.delete('dismissed_isbn_link');
      await txn.delete('user_book');
      await txn.delete('sync_meta');
    });
    await _clearMemoImages();
  }

  static Future<void> _clearMemoImages() async {
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory(join(root.path, 'memo_images'));
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      developer.log('[메모 사진 전체 정리] result=FAIL reason=local_file_error');
    }
  }
}
