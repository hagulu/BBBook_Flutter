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
      version: 10,
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
        if (oldVersion < 8) {
          // 메모 저장/수정/삭제에 서버 동기화(dirty push + 전체/증분 새로고침)를
          // 붙이며 로컬 PK(`id`)와 서버 PK를 분리한다. `id`는 오프라인에서
          // 즉시 부여하는 음수 임시값일 수 있어(book_memo_dao._nextLocalId) 더
          // 이상 "서버에 존재하는 실제 ID"라는 보장이 없다 — 그런데
          // `book_memo_item.memo_id` 외래 키(ON DELETE CASCADE, ON UPDATE
          // 없음)가 그 `id`를 그대로 참조하므로, push 성공 후 `id`를 서버
          // 값으로 바꿔치기(remap)하면 CASCADE 없이 자식 FK가 끊어지거나(v8
          // 이전) 자식을 다시 연결하는 별도 트랜잭션이 필요해진다. 대신
          // `server_id`를 별도 컬럼으로 둬 `id`는 절대 바뀌지 않게 하고(상세
          // 화면이 들고 있는 memoId 캐시가 push 이후에도 계속 유효),
          // PATCH/DELETE 등 서버 호출에는 `server_id`만 쓴다. 이 컬럼이
          // null이면 "아직 서버에 한 번도 반영되지 못한 로컬 전용 행"이라는
          // 뜻이 되어 dirty push 대상 판별에도 쓰인다.
          //
          // v6 이하에서 v8로 건너뛰어 업그레이드하면 바로 위 `oldVersion < 7`
          // 블록이 이미 `_createRecordTables()`(server_id 포함 최신 스키마)로
          // 테이블을 새로 만들어 컬럼이 이미 존재한다 — 그 상태에서 아래
          // ALTER를 또 실행하면 `duplicate column name`으로 DB 오픈 자체가
          // 실패한다. `PRAGMA table_info`로 컬럼 존재 여부를 먼저 확인해
          // v7에서 v8로 올라오는 경우에만 실제로 컬럼을 추가한다(건너뛰기
          // 업그레이드는 어차피 그 블록에서 테이블이 빈 채로 새로 만들어져
          // 백필할 대상 자체가 없다).
          if (await _hasTable(db, 'book_memo') &&
              !await _hasColumn(db, 'book_memo', 'server_id')) {
            await db.execute(
              'ALTER TABLE book_memo ADD COLUMN server_id INTEGER',
            );
            await db.execute(
              'ALTER TABLE book_memo_item ADD COLUMN server_id INTEGER',
            );
            // v7에도 이미 `_nextLocalId` 기반 로컬 전용 생성(오프라인
            // 메모/조각 작성, 음수 `id`)이 있었다 — 이번 작업 이전에는
            // 그 행을 서버로 push하는 경로가 아예 없었을 뿐, "로컬에만
            // 있고 아직 서버에 반영되지 못한 dirty 행"은 이미 존재할 수
            // 있었다. 그런 행까지 `server_id = id`(음수)로 채우면 이후
            // push가 "이미 서버에 있는 행"으로 오인해 존재하지도 않는
            // 음수 ID로 PATCH/DELETE를 반복하며 dirty가 영영 풀리지
            // 않는다. `id > 0`인 행(=서버 GET 응답으로 들어온, 확실히
            // 서버에 존재하는 행)만 백필하고, 음수 ID 행은 server_id를
            // NULL로 남겨 다음 push가 생성(POST/PUT) 경로를 타게 한다.
            await db.execute(
              'UPDATE book_memo SET server_id = id WHERE id > 0',
            );
            await db.execute(
              'UPDATE book_memo_item SET server_id = id WHERE id > 0',
            );
          }
        }
        if (oldVersion < 9) {
          // CREATE 멱등 키는 최초 로컬 생성 때 한 번 발급해 행과 함께
          // 보존한다. user_book은 이제 로컬 음수 PK와 서버 PK를 분리해,
          // 서버 ID가 없는 dirty 행만 POST 재시도 대상으로 판별한다.
          if (!await _hasColumn(db, 'user_book', 'server_id')) {
            await db.execute(
              'ALTER TABLE user_book ADD COLUMN server_id INTEGER',
            );
            await db.execute(
              'ALTER TABLE user_book ADD COLUMN client_request_id TEXT',
            );
            await db.execute(
              'ALTER TABLE user_book ADD COLUMN create_thumbnail_path TEXT',
            );
            await db.execute(
              'UPDATE user_book SET server_id = user_book_id '
              'WHERE user_book_id > 0',
            );
          }
          if (await _hasTable(db, 'book_memo_item') &&
              !await _hasColumn(db, 'book_memo_item', 'client_request_id')) {
            await db.execute(
              'ALTER TABLE book_memo_item '
              'ADD COLUMN client_request_id TEXT',
            );
          }
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_user_book_server_id '
            'ON user_book(server_id) WHERE server_id IS NOT NULL',
          );
        }
        // v10: 백엔드가 메모(Memo/MemoItem) 도메인을 노트(Note/NoteMemo)로
        // 개편해 클라이언트도 같은 명칭(`book_note`/`book_note_memo`)으로
        // 맞춘다. 이 앱은 아직 배포 전이라 기존 로컬 데이터 보존이 필요
        // 없어(재설치로 대응) 별도 업그레이드 블록을 두지 않는다 — 새
        // 스키마는 `onCreate`/`_createRecordTables`에만 반영한다.
      },
      onCreate: (db, version) async {
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
        await db.execute(
          'CREATE UNIQUE INDEX idx_user_book_server_id '
          'ON user_book(server_id) WHERE server_id IS NOT NULL',
        );
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

  static Future<bool> _hasColumn(
    Database db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }

  static Future<bool> _hasTable(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
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
  /// `owner_user_id`는 API 응답 필드가 아닌 로컬 계정 격리용 값이다. 서버에서
  /// 받은 행은 서버 PK(`id`)와 관계 키(`user_book_id`, `note_id`)를 원형
  /// 그대로 유지한다. 현재 전체 조회 응답에 없는 서버 삭제/수정 시각 컬럼은
  /// 향후 증분 동기화를 위해 nullable로 준비한다.
  ///
  /// `book_note`/`book_note_memo`의 `server_id`는 `id`와 별도의 컬럼이다.
  /// 노트/메모는 오프라인에서 즉시 로컬 음수 ID로 생성될 수 있는데(
  /// `BookNoteDao._nextLocalId`), 그 상태의 `id`는 서버에 아직 존재하지
  /// 않는다. push가 성공하면 서버가 내려준 진짜 ID를 `server_id`에 채우고
  /// `id`는 그대로 둔다 — `id`를 서버 값으로 바꿔치기하면
  /// `book_note_memo.note_id`(ON DELETE CASCADE, ON UPDATE 없음) FK가
  /// 깨지고, 상세 화면이 들고 있는 noteId 캐시도 함께 무효화된다. PATCH/DELETE
  /// 등 서버 호출은 항상 `server_id`를 쓰고, `server_id IS NULL`이면 "아직
  /// 서버에 한 번도 반영되지 못한 로컬 전용 행"이라는 뜻이다.
  static Future<void> _createRecordTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_note (
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_book_note_owner_user_book '
      'ON book_note(owner_user_id, user_book_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_note_memo (
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
        is_dirty INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (note_id) REFERENCES book_note(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_book_note_memo_note_sort '
      'ON book_note_memo(note_id, sort_order)',
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
      await txn.delete('book_note_memo');
      await txn.delete('book_note');
      await txn.delete('book_reflection');
      await txn.delete('user_book_tag');
      await txn.delete('dismissed_isbn_link');
      await txn.delete('user_book');
      await txn.delete('sync_meta');
    });
    await _clearMemoImages();
    await _clearPendingBookThumbnails();
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

  static Future<void> _clearPendingBookThumbnails() async {
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory(join(root.path, 'pending_book_thumbnails'));
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      developer.log('[책 표지 전체 정리] result=FAIL reason=local_file_error');
    }
  }
}
