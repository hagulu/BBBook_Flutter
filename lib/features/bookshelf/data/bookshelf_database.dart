import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../book_note/services/note_memo_image_store.dart';
import '../../book_reflection/services/reflection_image_store.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import '../services/book_cover_image_store.dart';

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
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
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
            stats_total_pages INTEGER,
            display_total_pages INTEGER,
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
            want_to_reread INTEGER NOT NULL DEFAULT 0,
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
            dirty_fields TEXT,
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
        await _createReflectionImageLocalTable(db);
        await _createStorageModeTable(db);
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

  /// 저장 모드(서버/로컬)를 담는 한 행짜리 로컬 테이블([StorageModeStore]).
  ///
  /// `server_delete_pending`은 "로컬 모드로 전환은 됐지만 서버 기록 정리가
  /// 아직 안 끝남"을 앱 재시작 뒤에도 기억하기 위한 값이다 — 이 값이 없으면
  /// 전환 직후 삭제가 실패했을 때 다시 시도할 방법이 사라진다.
  ///
  /// 행이 없으면 기본값인 서버 저장 모드다 — 자발적 로그아웃이 실행하는
  /// [clearAll]이 이 행을 지우므로, 로컬 데이터가 사라지는 순간 모드도 함께
  /// 초기화된다.
  static Future<void> _createStorageModeTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS storage_mode (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        mode TEXT NOT NULL,
        owner_user_id INTEGER,
        server_delete_pending INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// 독후감 본문 이미지의 "서버 URL ↔ 로컬 사본" 짝을 담는 로컬 전용 테이블.
  ///
  /// 서버 `book_reflection.content_json`은 이미지 URL만 갖고 기기 로컬 경로는
  /// 모른다. 그래서 화면이 로컬 파일을 우선 표시하려면 이 매칭이 따로
  /// 필요하다(`reflectionImageStore`가 실제 파일을 관리한다).
  ///
  /// 일부러 `book_reflection`을 참조하는 외래 키를 걸지 않는다 — 독후감 행은
  /// 동기화 반영 때 `INSERT OR REPLACE`로 갱신되는데(REPLACE는 기존 행을 지운
  /// 뒤 다시 넣는다) ON DELETE CASCADE를 걸면 동기화 한 번에 매칭이 통째로
  /// 사라진다(v5 `dismissed_isbn_link`와 같은 함정). 독후감이 실제로 사라졌을
  /// 때의 정리는 `BookReflectionRepository.hydrateLocalImages()`가 직접 한다.
  static Future<void> _createReflectionImageLocalTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reflection_image_local (
        reflection_id INTEGER NOT NULL,
        remote_image_url TEXT NOT NULL,
        local_image_path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (reflection_id, remote_image_url)
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
  ///
  /// `book_note_memo`의 사진은 두 컬럼으로 나뉜다. `image_url`은 서버가
  /// 내려준 전체 URL 전용이고(null이면 "아직 서버에 올리지 못한 사진"),
  /// `local_image_path`는 서버에 없는 로컬 전용 정보로 앱 지원 디렉터리
  /// 기준 상대 경로를 담는다(`noteMemoImageStore`). 화면은 로컬 파일을
  /// 먼저 쓰고 없을 때만 `image_url`로 대체한다.
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
        local_image_path TEXT,
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
        server_id INTEGER,
        client_request_id TEXT,
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
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_book_reflection_server_id '
      'ON book_reflection(server_id) WHERE server_id IS NOT NULL',
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
      await txn.delete('reflection_image_local');
      await txn.delete('book_reflection');
      await txn.delete('user_book_tag');
      await txn.delete('dismissed_isbn_link');
      await txn.delete('user_book');
      await txn.delete('sync_meta');
      await txn.delete('storage_mode');
    });
    storageModeStore.invalidateCache();
    await noteMemoImageStore.clear();
    await reflectionImageStore.clear();
    await bookCoverImageStore.clear();
    await _clearPendingBookThumbnails();
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
