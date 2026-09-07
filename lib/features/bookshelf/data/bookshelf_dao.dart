import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/book_item.dart';
import '../models/book_status.dart';
import '../models/book_tag.dart';
import '../models/finished_filter.dart';
import '../models/record_patch.dart';
import '../models/user_book_create_result.dart';
import 'bookshelf_database.dart';

/// 아직 서버에 반영되지 못한 로컬 편집 한 건.
///
/// [baseUpdatedAt]은 이 편집이 기준으로 삼은 서버 `updated_at`(낙관적 동시성
/// 검사용, 모르면 null)이고, [changedFields]는 편집이 실제로 건드린 PATCH
/// 필드 이름이다 — null이면 `dirty_fields` 컬럼이 없던 시절(DB v15 이하)에
/// 쌓인 행이라 무엇을 바꿨는지 알 수 없다([RecordPatch.fromSnapshot] 참고).
typedef DirtyRecord = ({
  BookItem item,
  DateTime? baseUpdatedAt,
  Set<String>? changedFields,
});

/// 책장 로컬 DB 쿼리/쓰기 전담.
///
/// `is_dirty = 1`인 로컬 행은 [reconcile](전체 동기화)/[applyChanges](증분
/// 동기화) 모두 서버 데이터로 덮어쓰거나 삭제하지 않는다 — [applyLocalEdit]로
/// 표시된 책 기록 화면의 로컬 우선 수정을 동기화가 지우지 않게 하기 위함이다.
/// dirty 행은 [confirmPush](서버 push 성공)나 [resolveConflict](409 충돌)를
/// 통해서만 해제된다.
class BookshelfDao {
  const BookshelfDao();

  Future<BookItem?> getById(int userBookId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'user_book',
      where: 'user_book_id = ?',
      whereArgs: [userBookId],
    );
    if (rows.isEmpty) return null;
    final items = await _attachTags(db, rows);
    return items.first;
  }

  Future<BookItem?> getByIsbn13(String isbn13) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'user_book',
      where: 'isbn13 = ?',
      whereArgs: [isbn13],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (await _attachTags(db, rows)).single;
  }

  Future<List<BookItem>> getByStatuses(List<BookStatus> statuses) async {
    final db = await BookshelfDatabase.instance();
    final placeholders = List.filled(statuses.length, '?').join(', ');
    final rows = await db.query(
      'user_book',
      where: 'status IN ($placeholders)',
      whereArgs: statuses.map((s) => s.apiValue).toList(),
      orderBy: 'user_book_id DESC',
    );
    return _attachTags(db, rows);
  }

  Future<List<BookItem>> getGrid(BookStatus status) => getByStatuses([status]);

  Future<List<BookItem>> searchFinished(FinishedFilter filter) async {
    final db = await BookshelfDatabase.instance();
    final where = <String>['status = ?'];
    final args = <Object?>[BookStatus.finished.apiValue];

    if (filter.keyword.isNotEmpty) {
      where.add('(title LIKE ? OR author LIKE ? OR publisher LIKE ?)');
      final kw = '%${filter.keyword}%';
      args.addAll([kw, kw, kw]);
    }
    if (filter.categories.isNotEmpty) {
      final placeholders = List.filled(
        filter.categories.length,
        '?',
      ).join(', ');
      where.add('category IN ($placeholders)');
      args.addAll(filter.categories);
    }
    if (filter.masterpieceOnly) {
      where.add('is_masterpiece = 1');
    }
    if (filter.difficulty != null) {
      where.add('difficulty = ?');
      args.add(filter.difficulty);
    }
    if (filter.tagIds.isNotEmpty) {
      final placeholders = List.filled(filter.tagIds.length, '?').join(', ');
      where.add(
        'user_book_id IN (SELECT user_book_id FROM user_book_tag_map '
        'WHERE deleted_at IS NULL AND tag_id IN ($placeholders))',
      );
      args.addAll(filter.tagIds);
    }

    final rows = await db.query(
      'user_book',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'finished_at DESC, user_book_id DESC',
    );
    return _attachTags(db, rows);
  }

  /// 완독 목록 "ISBN 미연결" 배너에서 "목록에서 제외"를 켠 채 건너뛴 책을
  /// 기록한다(이미 있으면 dismissed_at만 갱신). `unlinkedFinishedBooksProvider`가
  /// 다음부터 이 책을 미연결 개수/목록에서 뺀다.
  Future<void> markIsbnLinkDismissed(int userBookId) async {
    final db = await BookshelfDatabase.instance();
    await db.insert('dismissed_isbn_link', {
      'user_book_id': userBookId,
      'dismissed_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Set<int>> getDismissedIsbnLinkUserBookIds() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'dismissed_isbn_link',
      columns: ['user_book_id'],
    );
    return rows.map((r) => r['user_book_id'] as int).toSet();
  }

  Future<List<String>> getDistinctCategories() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.rawQuery(
      'SELECT DISTINCT category FROM user_book WHERE status = ? AND category IS NOT NULL '
      'ORDER BY category',
      [BookStatus.finished.apiValue],
    );
    return rows.map((r) => r['category'] as String).toList();
  }

  Future<List<BookTag>> getDistinctTags() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT t.id, t.name
      FROM tag t
      INNER JOIN user_book_tag_map m ON m.tag_id = t.id AND m.deleted_at IS NULL
      INNER JOIN user_book b ON b.user_book_id = m.user_book_id
      WHERE t.deleted_at IS NULL AND b.status = ?
      ORDER BY t.name
      ''',
      [BookStatus.finished.apiValue],
    );
    return rows
        .map((r) => BookTag(id: r['id'] as int, name: r['name'] as String))
        .toList();
  }

  Future<DateTime?> getLastSyncedAt() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['last_synced_at'],
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['value'] as String);
  }

  /// 서버 전체 스냅샷으로 로컬 DB를 맞춘다: 서버에 있는 행은 upsert, 서버에
  /// 없는(로컬에만 남은) 비-dirty 행은 삭제. dirty 행은 upsert도 삭제도 하지 않는다.
  ///
  /// [requestedAt]은 이 전체 동기화 요청을 보내기 *직전* 시각(UTC)이어야 한다.
  /// 응답을 받은 뒤의 시각을 쓰면 그 사이 서버에 반영된 변경이 다음 증분
  /// 동기화의 since보다 앞서게 되어 영구히 누락될 수 있다.
  Future<void> reconcile(
    List<BookItem> serverItems,
    DateTime requestedAt,
  ) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction(
      (txn) => reconcileInTransaction(txn, serverItems, requestedAt),
    );
  }

  /// 통합 최초 조회처럼 책장 외 데이터와 같은 트랜잭션에 전체 스냅샷을
  /// 저장해야 하는 호출을 위한 transaction 버전이다.
  Future<void> reconcileInTransaction(
    Transaction txn,
    List<BookItem> serverItems,
    DateTime requestedAt, {
    void Function()? onItemSaved,
  }) async {
    final serverIds = serverItems
        .map((e) => e.serverId ?? e.userBookId)
        .toList();

    for (final item in serverItems) {
      await _upsertItemTxn(txn, item, syncedUpdatedAt: item.updatedAt);
      onItemSaved?.call();
    }

    final deletableWhere = serverIds.isEmpty
        ? 'is_dirty = 0'
        : '(server_id IS NULL OR server_id NOT IN '
              '(${List.filled(serverIds.length, '?').join(', ')})) '
              'AND is_dirty = 0';
    final deletableRows = await txn.query(
      'user_book',
      columns: ['user_book_id'],
      where: deletableWhere,
      whereArgs: serverIds.isEmpty ? null : serverIds,
    );
    final deletableUserBookIds = deletableRows
        .map((r) => r['user_book_id'] as int)
        .toList(growable: false);
    if (deletableUserBookIds.isNotEmpty) {
      final idPlaceholders = List.filled(
        deletableUserBookIds.length,
        '?',
      ).join(', ');
      await txn.delete(
        'user_book',
        where: 'user_book_id IN ($idPlaceholders)',
        whereArgs: deletableUserBookIds,
      );
      // user_book_tag_map은 REPLACE-CASCADE 함정을 피하려 외래 키가 없어
      // 직접 정리해야 한다([BookshelfDatabase._createTagTables] 참고) —
      // 그러지 않으면 삭제된 책이 남긴 태그 매핑이 [_nextLocalUserBookId]가
      // 재사용하는 음수 로컬 ID를 통해 이후 다른 책에 붙는다.
      await txn.delete(
        'user_book_tag_map',
        where: 'user_book_id IN ($idPlaceholders)',
        whereArgs: deletableUserBookIds,
      );
    }
    await _pruneOrphanedDismissalsTxn(txn);

    await txn.insert('sync_meta', {
      'key': 'last_synced_at',
      'value': requestedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 증분 동기화 결과를 로컬 DB에 반영한다: upserted 항목은 upsert, deletedUserBookIds는
  /// 삭제. 둘 다 dirty 행은 건드리지 않는다([reconcile]과 동일한 보호 정책).
  /// 반영이 전부 끝난 트랜잭션 안에서만 다음 since 기준값(syncedAt)을 갱신하므로,
  /// 도중에 실패하면 기준값은 그대로 남아 다음 시도에서 같은 구간을 다시 받는다.
  Future<void> applyChanges({
    required List<BookItem> upserted,
    required List<int> deletedUserBookIds,
    required DateTime syncedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      for (final item in upserted) {
        await _upsertItemTxn(txn, item, syncedUpdatedAt: item.updatedAt);
      }

      if (deletedUserBookIds.isNotEmpty) {
        final placeholders = List.filled(
          deletedUserBookIds.length,
          '?',
        ).join(', ');
        final deletableRows = await txn.query(
          'user_book',
          columns: ['user_book_id'],
          where: 'server_id IN ($placeholders) AND is_dirty = 0',
          whereArgs: deletedUserBookIds,
        );
        final deletableUserBookIds = deletableRows
            .map((r) => r['user_book_id'] as int)
            .toList(growable: false);
        await txn.delete(
          'user_book',
          where: 'server_id IN ($placeholders) AND is_dirty = 0',
          whereArgs: deletedUserBookIds,
        );
        // user_book_tag_map 정리 이유는 [reconcileInTransaction] 문서 참고.
        if (deletableUserBookIds.isNotEmpty) {
          final idPlaceholders = List.filled(
            deletableUserBookIds.length,
            '?',
          ).join(', ');
          await txn.delete(
            'user_book_tag_map',
            where: 'user_book_id IN ($idPlaceholders)',
            whereArgs: deletableUserBookIds,
          );
        }
      }
      await _pruneOrphanedDismissalsTxn(txn);

      await txn.insert('sync_meta', {
        'key': 'last_synced_at',
        'value': syncedAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// 책 기록 화면에서 서버 PATCH가 성공한 뒤 그 결과 한 건만 로컬에 반영할 때
  /// 쓴다. [reconcile]/[applyChanges]와 동일하게 dirty 행은 덮어쓰지 않고,
  /// `sync_meta.last_synced_at`은 건드리지 않는다(다음 증분 동기화가 이
  /// 행을 다시 upsert하는 것은 무해하다).
  ///
  /// [syncedUpdatedAt]은 응답에 실제 서버 `updated_at`이 함께 내려오는
  /// 호출(책 정보 PATCH)만 넘긴다 — 태그 추가/삭제처럼 클라이언트 시각으로
  /// [item.updatedAt]을 채운 호출은 생략해 기존 충돌 검사 기준값을
  /// 그대로 보존해야 한다(그러지 않으면 다음 record PATCH의 충돌 검사가
  /// 실제로 존재하지 않는 서버 시각을 기준으로 잘못 비교된다).
  Future<void> upsertOne(BookItem item, {DateTime? syncedUpdatedAt}) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction(
      (txn) => _upsertItemTxn(txn, item, syncedUpdatedAt: syncedUpdatedAt),
    );
  }

  /// 서재에서 책을 삭제(DELETE API 성공)한 뒤 로컬 행을 제거하고, 그 책의
  /// ISBN 일괄 연결 "제외" 기록(있다면)도 함께 지운다(`dismissed_isbn_link`는
  /// `user_book`을 외래 키로 참조하지 않아 자동으로 정리되지 않는다 —
  /// bookshelf_database.dart의 `_createDismissedIsbnLinkTable` 문서 참고).
  /// 책 한 권과 그 아래 기록(노트·메모·독후감·이미지 매칭·제외 표시)을
  /// 한 트랜잭션에서 모두 지운다.
  ///
  /// `book_note`/`book_reflection`은 일부러 `user_book` 외래 키를 걸지 않아
  /// (동기화가 `INSERT OR REPLACE`를 쓰기 때문 —
  /// `BookshelfDatabase._createRecordTables` 참고) CASCADE가 없다. 여기서
  /// 직접 지우지 않으면 하위 기록이 남고, 로컬 신규 책 ID는
  /// [_nextLocalUserBookId]가 `MIN(user_book_id) - 1`로 발급하므로 지운 책이
  /// 가장 작은 음수였다면 그 ID가 다음 책에 재사용되면서 남은 노트·독후감이
  /// 엉뚱한 책에 다시 붙는다.
  Future<void> deleteOne(int userBookId) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await txn.delete(
        'book_note_memo',
        where: 'note_id IN (SELECT id FROM book_note WHERE user_book_id = ?)',
        whereArgs: [userBookId],
      );
      await txn.delete(
        'book_note',
        where: 'user_book_id = ?',
        whereArgs: [userBookId],
      );
      await txn.delete(
        'reflection_image_local',
        where:
            'reflection_id IN '
            '(SELECT id FROM book_reflection WHERE user_book_id = ?)',
        whereArgs: [userBookId],
      );
      await txn.delete(
        'book_reflection',
        where: 'user_book_id = ?',
        whereArgs: [userBookId],
      );
      // user_book_tag_map도 같은 이유(REPLACE-CASCADE 함정)로 외래 키가 없어
      // 직접 지워야 한다 — 책이 서버에서 삭제되면 그 아래 매핑도 서버가 함께
      // soft delete하므로(api-doc), 여기서는 서버 push 없이 로컬 정리만 한다.
      await txn.delete(
        'user_book_tag_map',
        where: 'user_book_id = ?',
        whereArgs: [userBookId],
      );
      await txn.delete(
        'user_book',
        where: 'user_book_id = ?',
        whereArgs: [userBookId],
      );
      await txn.delete(
        'dismissed_isbn_link',
        where: 'user_book_id = ?',
        whereArgs: [userBookId],
      );
    });
  }

  /// [deleteOne] 전에 호출해, 이 책과 함께 지워야 할 로컬 이미지 파일의
  /// 상대 경로를 모은다(행을 지우면 어떤 파일이 딸려 있었는지 알 수 없다).
  Future<BookLocalImagePaths> findLocalImagePathsForBook(int userBookId) async {
    final db = await BookshelfDatabase.instance();
    final memoRows = await db.rawQuery(
      'SELECT m.local_image_path AS path FROM book_note_memo m '
      'JOIN book_note n ON n.id = m.note_id '
      'WHERE n.user_book_id = ? AND m.local_image_path IS NOT NULL',
      [userBookId],
    );
    final reflectionRows = await db.rawQuery(
      'SELECT l.local_image_path AS path FROM reflection_image_local l '
      'JOIN book_reflection r ON r.id = l.reflection_id '
      'WHERE r.user_book_id = ?',
      [userBookId],
    );
    final coverRows = await db.query(
      'user_book',
      columns: ['cover_image_url'],
      where: 'user_book_id = ?',
      whereArgs: [userBookId],
      limit: 1,
    );
    return BookLocalImagePaths(
      memoImages: memoRows
          .map((row) => row['path'] as String)
          .toList(growable: false),
      reflectionImages: reflectionRows
          .map((row) => row['path'] as String)
          .toList(growable: false),
      coverImage: coverRows.isEmpty
          ? null
          : coverRows.single['cover_image_url'] as String?,
    );
  }

  /// [reconcile]/[applyChanges]가 실제로 `user_book` 행을 지운 뒤 호출한다.
  /// `dismissed_isbn_link`가 `user_book`을 외래 키로 참조하지 않으므로(이유는
  /// bookshelf_database.dart의 `_createDismissedIsbnLinkTable` 참고) 더 이상
  /// 존재하지 않는 user_book_id를 가리키는 제외 기록을 여기서 직접 청소한다.
  /// dirty라서 이번에 실제로 지워지지 않은 행은 `user_book`에 그대로
  /// 남아 있으므로 이 조건에 걸리지 않는다.
  Future<void> _pruneOrphanedDismissalsTxn(Transaction txn) async {
    await txn.delete(
      'dismissed_isbn_link',
      where: 'user_book_id NOT IN (SELECT user_book_id FROM user_book)',
    );
  }

  /// 책 기록 화면의 필드 수정을 로컬에 즉시 반영하고 `is_dirty = 1`로
  /// 표시한다. [_upsertItemTxn]과 달리 이미 dirty인 행도 덮어쓴다(오프라인
  /// 중 같은 책을 연달아 수정하면 최신 값으로 계속 갱신되어야 하므로).
  /// `synced_updated_at`(서버 충돌 검사 기준값)은 항상 기존 값을 그대로
  /// 유지한다 — 이 값은 서버 GET 응답으로만 갱신되어야 하며, 연속된 로컬
  /// 편집마다 새로 잡으면 첫 오프라인 편집 이전의 서버 상태를 기준으로 한
  /// 충돌 검사가 불가능해진다.
  ///
  /// [changedFields]는 이번 편집이 실제로 건드린 PATCH 필드 이름
  /// ([RecordPatch.changedFields])이고, 아직 push되지 못한 이전 편집의
  /// 목록과 합집합으로 누적한다(`dirty_fields`). 나중에 push할 때 이 목록에
  /// 있는 필드만 요청 body에 실어야 사용자가 건드리지 않은 필드는 서버 값이
  /// 유지되고, 사용자가 지운 필드는 명시적 null(삭제)로 나간다.
  ///
  /// 이미 dirty인데 목록이 없는 행은 `dirty_fields` 컬럼이 없던 시절(DB v15
  /// 이하)에 쌓인 레거시 편집이다 — 그 행이 지금까지 보내던 것과 같은 집합
  /// ([RecordPatch.nonNullFieldsOf])을 출발점으로 삼아, 아직 못 올린 이전
  /// 편집이 이번 목록 밖으로 떨어져 나가지 않게 한다.
  Future<void> applyLocalEdit(
    BookItem item, {
    required Set<String> changedFields,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final existing = await _readDirtyState(txn, item.userBookId);
      final pendingFields = existing.isDirty
          ? (existing.dirtyFields ?? RecordPatch.nonNullFieldsOf(item))
          : const <String>{};
      await txn.insert('user_book', {
        ..._bookItemToRow(item),
        'is_dirty': 1,
        'synced_updated_at': existing.syncedUpdatedAt,
        'dirty_fields': _encodeDirtyFields({
          ...pendingFields,
          ...changedFields,
        }),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// 서버 요청 전에 로컬 CREATE 행을 먼저 만든다. [item.clientRequestId]는
  /// 호출부가 이 로컬 생성 작업을 시작하며 발급한 UUID이고, 이후 모든 dirty
  /// POST 재시도에서 이 컬럼을 그대로 읽어 사용한다.
  Future<BookItem> insertLocalCreate(BookItem item) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final localId = await _nextLocalUserBookId(txn);
      final values = <String, Object?>{
        ..._bookItemToRow(item),
        'user_book_id': localId,
        'server_id': null,
        'is_dirty': 1,
        'synced_updated_at': null,
        // CREATE는 필드 전체를 한 번에 올리므로 추적 목록이 필요 없다. 이
        // 행에 로컬 편집이 겹치면 그때부터 [applyLocalEdit]가 목록을 쌓고,
        // CREATE가 확정된 뒤의 재시도는 그 목록으로 PATCH한다.
        'dirty_fields': null,
      };
      await txn.insert('user_book', values);
      return _rowToBookItem(values, const []);
    });
  }

  /// CREATE 성공 또는 동일 clientRequestId 재시도로 기존 서버 행을 반환받은
  /// 뒤 실제 서버 ID를 확정한다. 네트워크 왕복 중 로컬 편집이 없었을 때만
  /// 응답 필드로 확정하고 dirty를 해제하며, 편집이 있었다면 server_id만
  /// 채우고 dirty는 유지해 다음 push가 UPDATE로 이어지게 한다.
  Future<bool> confirmCreate({
    required int localId,
    required DateTime capturedUpdatedAt,
    required UserBookCreateResult response,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'user_book',
        columns: ['updated_at'],
        where: 'user_book_id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final current = DateTime.parse(rows.single['updated_at'] as String);
      final unchanged = current.isAtSameMomentAs(capturedUpdatedAt);
      await txn.update(
        'user_book',
        {
          'server_id': response.userBookId,
          'book_id': response.bookId,
          'isbn13': response.isbn13,
          'create_thumbnail_path': null,
          if (unchanged) ...{
            'title': response.title,
            'author': response.author,
            'publisher': response.publisher,
            'stats_total_pages': response.statsTotalPages,
            'display_total_pages': response.displayTotalPages,
            'cover_image_url': response.coverImageUrl,
            'status': response.status,
            'is_dirty': 0,
            'dirty_fields': null,
          },
        },
        where: 'user_book_id = ?',
        whereArgs: [localId],
      );
      return unchanged;
    });
  }

  /// dirty 행의 서버 push가 성공한 뒤 그 응답으로 확정 반영한다. dirty
  /// 여부와 무관하게 덮어쓴다(이 호출 자체가 dirty를 해제하는 동작이므로
  /// [_upsertItemTxn]의 "dirty면 건드리지 않음" 보호를 적용하면 안 된다).
  /// `synced_updated_at`은 [item.updatedAt](PATCH 응답의 실제 서버
  /// `updated_at`, api-doc 기준)으로 갱신한다 — 다음 push가 이 값을 충돌
  /// 검사 기준으로 즉시 쓸 수 있어, 다음 동기화(GET)를 기다릴 필요가 없다.
  ///
  /// [capturedUpdatedAt]은 이 push 요청을 만들 때 읽은 로컬 `updated_at`이다.
  /// 네트워크 왕복 동안 사용자가 같은 책을 또 편집했으면(로컬 편집은 push
  /// 큐를 기다리지 않고 즉시 반영된다) 그 값과 달라지는데, 그때 서버 응답을
  /// 덮어쓰면 방금 한 편집과 아직 보내지 못한 [DirtyRecord.changedFields]가
  /// 통째로 사라진다. 그래서 확인과 쓰기를 한 트랜잭션에서 처리하고(중간에
  /// 다른 쓰기가 끼어들 수 없다), 값이 달라졌으면 필드와 dirty 상태는 그대로
  /// 둔 채 다음 push의 충돌 검사 기준값만 갱신한다.
  ///
  /// 반환값은 서버 응답이 실제로 반영됐는지 여부(행이 사라졌으면 false).
  Future<bool> confirmPush(
    BookItem item, {
    required DateTime capturedUpdatedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'user_book',
        columns: ['updated_at'],
        where: 'user_book_id = ?',
        whereArgs: [item.userBookId],
        limit: 1,
      );
      // push가 오가는 사이 이 책이 로컬에서 사라졌다(동시 삭제 등) — 이미
      // 지워진 책을 응답으로 되살리지 않는다.
      if (rows.isEmpty) return false;
      final syncedUpdatedAt = item.updatedAt.toUtc().toIso8601String();
      final current = DateTime.parse(rows.single['updated_at'] as String);
      if (!current.isAtSameMomentAs(capturedUpdatedAt)) {
        await txn.update(
          'user_book',
          {'synced_updated_at': syncedUpdatedAt},
          where: 'user_book_id = ?',
          whereArgs: [item.userBookId],
        );
        return false;
      }
      await txn.insert('user_book', {
        ..._bookItemToRow(item),
        'is_dirty': 0,
        'synced_updated_at': syncedUpdatedAt,
        'dirty_fields': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  /// 서버 push가 409(다른 곳에서 이미 수정됨)로 거부됐을 때 호출한다. 이
  /// 행의 로컬 편집을 서버가 거부했으므로 dirty를 해제해 다음 동기화가
  /// 다시 덮어쓸 수 있게 하고, `sync_meta.last_synced_at`도 함께 지워
  /// 다음 [BookshelfRepository.sync] 호출이 증분이 아닌 전체 동기화로
  /// 이 행(과 그 사이 놓쳤을 수 있는 다른 변경)을 다시 받아오게 한다 —
  /// 이미 지난 since 이후로 넘어간 증분 동기화는 이 행을 다시 내려주지
  /// 않을 수 있다(단건 조회 API가 없어 전체 동기화가 유일한 복구 수단).
  ///
  /// 단, 거부된 요청이 오가는 사이 사용자가 새로 편집했으면([capturedUpdatedAt]
  /// 과 현재 로컬 값이 다르면) dirty와 바꾼 필드 목록을 그대로 남긴다 —
  /// 서버가 거부한 것은 그 이전 스냅샷이지 방금 한 편집이 아니라서, 여기서
  /// dirty를 풀면 이어질 전체 동기화가 아직 보내지도 못한 편집을 조용히
  /// 덮어쓴다. 이 경우 기준값(`synced_updated_at`)만 비워 다음 push가 충돌
  /// 검사 없이(=사용자의 최신 편집을 우선해서) 나가게 한다.
  ///
  /// 반환값은 로컬 편집을 실제로 되돌렸는지 여부.
  Future<bool> resolveConflict(
    int userBookId, {
    required DateTime capturedUpdatedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'user_book',
        columns: ['updated_at'],
        where: 'user_book_id = ?',
        whereArgs: [userBookId],
        limit: 1,
      );
      final current = rows.isEmpty
          ? null
          : DateTime.parse(rows.single['updated_at'] as String);
      final unchanged =
          current != null && current.isAtSameMomentAs(capturedUpdatedAt);
      if (current != null) {
        await txn.update(
          'user_book',
          unchanged
              ? {'is_dirty': 0, 'synced_updated_at': null, 'dirty_fields': null}
              : {'synced_updated_at': null},
          where: 'user_book_id = ?',
          whereArgs: [userBookId],
        );
      }
      await txn.delete(
        'sync_meta',
        where: 'key = ?',
        whereArgs: ['last_synced_at'],
      );
      return unchanged;
    });
  }

  /// 아직 서버에 반영되지 못한(is_dirty = 1) 행 전체를 push 기준값과 함께
  /// 반환한다. `BookshelfRepository.sync()`가 매 동기화 전에 일괄 재시도할
  /// 때 쓴다.
  Future<List<DirtyRecord>> getDirtyRecords() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query('user_book', where: 'is_dirty = 1');
    if (rows.isEmpty) return const [];
    final items = await _attachTags(db, rows);
    final rowById = {for (final row in rows) row['user_book_id'] as int: row};
    return items.map((item) {
      final row = rowById[item.userBookId];
      return (
        item: item,
        baseUpdatedAt: DateTime.tryParse(
          row?['synced_updated_at'] as String? ?? '',
        ),
        changedFields: _decodeDirtyFields(row?['dirty_fields'] as String?),
      );
    }).toList();
  }

  /// 특정 책이 dirty(is_dirty = 1)면 그 행과 push 기준값을 반환하고, 아니면
  /// (이미 push가 끝났거나 애초에 편집이 없었으면) null을 반환한다. 책 기록
  /// 화면이 편집 직후 시도하는 단건 즉시 push가 쓴다.
  Future<DirtyRecord?> getDirtyRecord(int userBookId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'user_book',
      where: 'user_book_id = ? AND is_dirty = 1',
      whereArgs: [userBookId],
    );
    if (rows.isEmpty) return null;
    final items = await _attachTags(db, rows);
    return (
      item: items.first,
      baseUpdatedAt: DateTime.tryParse(
        rows.first['synced_updated_at'] as String? ?? '',
      ),
      changedFields: _decodeDirtyFields(rows.first['dirty_fields'] as String?),
    );
  }

  /// 로컬 우선 편집을 덮어쓰기 전에 필요한 기존 행의 상태(충돌 검사 기준값과
  /// 아직 push되지 못한 편집 목록). 행이 없으면 모두 비어 있는 상태다.
  Future<({bool isDirty, String? syncedUpdatedAt, Set<String>? dirtyFields})>
  _readDirtyState(Transaction txn, int userBookId) async {
    final existing = await txn.query(
      'user_book',
      columns: ['is_dirty', 'synced_updated_at', 'dirty_fields'],
      where: 'user_book_id = ?',
      whereArgs: [userBookId],
      limit: 1,
    );
    if (existing.isEmpty) {
      return (isDirty: false, syncedUpdatedAt: null, dirtyFields: null);
    }
    return (
      isDirty: existing.first['is_dirty'] == 1,
      syncedUpdatedAt: existing.first['synced_updated_at'] as String?,
      dirtyFields: _decodeDirtyFields(
        existing.first['dirty_fields'] as String?,
      ),
    );
  }

  /// `dirty_fields`는 PATCH 필드 이름(영문/숫자)만 담으므로 쉼표로 잇는다.
  /// 빈 목록은 NULL로 저장한다 — 기록 필드를 하나도 건드리지 않은 로컬
  /// 편집(로컬 저장 모드의 책 정보 수정 등)이라 추적할 것이 없고,
  /// [RecordPatch.fromSnapshot]도 NULL과 빈 목록을 같게(레거시 스냅샷)
  /// 취급한다.
  static String? _encodeDirtyFields(Set<String> fields) =>
      fields.isEmpty ? null : fields.join(',');

  static Set<String>? _decodeDirtyFields(String? value) {
    if (value == null) return null;
    if (value.isEmpty) return const <String>{};
    return value.split(',').toSet();
  }

  Future<void> _upsertItemTxn(
    Transaction txn,
    BookItem item, {
    DateTime? syncedUpdatedAt,
  }) async {
    // 서버 ID가 없는 신규 로컬 행은 음수 local PK를 server_id에 쓰지 않는다.
    // CREATE 확정 직후 오래된 스냅샷이 들어와도 실제 server_id를 음수 값으로
    // 덮을 수 없도록 방어한다. 기존 양수 PK 행은 마이그레이션 호환을 위해
    // 종전처럼 PK를 서버 ID 대체값으로 허용한다.
    final incomingServerId =
        item.serverId ?? (item.userBookId > 0 ? item.userBookId : null);
    final existing = await txn.query(
      'user_book',
      columns: [
        'user_book_id',
        'server_id',
        'is_dirty',
        'synced_updated_at',
        'client_request_id',
        'create_thumbnail_path',
      ],
      where: incomingServerId == null
          ? 'user_book_id = ?'
          : 'server_id = ? OR user_book_id = ?',
      whereArgs: incomingServerId == null
          ? [item.userBookId]
          : [incomingServerId, item.userBookId],
      limit: 1,
    );
    final isDirtyLocally =
        existing.isNotEmpty && existing.first['is_dirty'] == 1;
    if (isDirtyLocally) return;

    // 호출부가 [syncedUpdatedAt]을 채워 보낼 때만(서버 GET 응답 —
    // reconcile/applyChanges, 또는 실제 서버 updated_at을 응답으로 받은
    // upsertOne 호출 — 책 정보 PATCH) 실제 서버 updated_at으로 갱신한다.
    // 그 외(태그 추가/삭제처럼 응답에 updated_at이 없어 클라이언트 시각으로
    // item.updatedAt을 채운 호출)는 기존 값을 그대로 이어간다 — 클라이언트
    // 시각을 대신 채우면 다음 push의 충돌 검사가 실제로 존재하지 않는 서버
    // 시각을 기준으로 비교돼 잘못된 409를 유발할 수 있다.
    final resolvedSyncedUpdatedAt =
        syncedUpdatedAt?.toUtc().toIso8601String() ??
        (existing.isEmpty
            ? null
            : existing.first['synced_updated_at'] as String?);

    final localId = existing.isEmpty
        ? item.userBookId
        : existing.first['user_book_id'] as int;
    final resolvedServerId =
        item.serverId ??
        (existing.isEmpty ? null : existing.first['server_id'] as int?) ??
        incomingServerId;
    await txn.insert('user_book', {
      ..._bookItemToRow(item),
      'user_book_id': localId,
      'server_id': resolvedServerId,
      'client_request_id':
          item.clientRequestId ??
          (existing.isEmpty
              ? null
              : existing.first['client_request_id'] as String?),
      'create_thumbnail_path':
          item.createThumbnailPath ??
          (existing.isEmpty
              ? null
              : existing.first['create_thumbnail_path'] as String?),
      'synced_updated_at': resolvedSyncedUpdatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 책 행에 활성 태그를 붙인다. 태그/매핑은 `TagDao`가 전담하는 별도
  /// 테이블(`tag`, `user_book_tag_map`)에 산다 — 책 upsert(REPLACE)가 태그를
  /// 함께 지우지 않도록 의도적으로 분리돼 있으므로(`BookshelfDatabase._createTagTables`
  /// 주석 참고) 여기서는 조회만 한다.
  Future<List<BookItem>> _attachTags(
    Database db,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r['user_book_id'] as int).toList();
    final placeholders = List.filled(ids.length, '?').join(', ');
    final tagRows = await db.rawQuery(
      '''
      SELECT m.user_book_id AS user_book_id, t.id AS tag_id, t.name AS tag_name
      FROM user_book_tag_map m
      INNER JOIN tag t ON t.id = m.tag_id
      WHERE m.user_book_id IN ($placeholders) AND m.deleted_at IS NULL
        AND t.deleted_at IS NULL
      ORDER BY t.name
      ''',
      ids,
    );
    final tagsByBook = <int, List<BookTag>>{};
    for (final t in tagRows) {
      final bookId = t['user_book_id'] as int;
      (tagsByBook[bookId] ??= []).add(
        BookTag(id: t['tag_id'] as int, name: t['tag_name'] as String),
      );
    }
    return rows
        .map(
          (r) => _rowToBookItem(
            r,
            tagsByBook[r['user_book_id'] as int] ?? const [],
          ),
        )
        .toList();
  }

  Map<String, Object?> _bookItemToRow(BookItem item) {
    return {
      'user_book_id': item.userBookId,
      'server_id': item.serverId,
      'book_id': item.bookId,
      'isbn13': item.isbn13,
      'title': item.title,
      'author': item.author,
      'publisher': item.publisher,
      'stats_total_pages': item.statsTotalPages,
      'display_total_pages': item.displayTotalPages,
      'cover_image_url': item.coverImageUrl,
      'display_category_id': item.displayCategoryId,
      'category': item.category,
      'status': item.status.apiValue,
      'current_page': item.currentPage,
      'my_rating': item.myRating,
      'short_review': item.shortReview,
      'is_masterpiece': item.isMasterpiece ? 1 : 0,
      'source_type': item.sourceType,
      'reread_count': item.rereadCount,
      'want_to_reread': item.wantToReread ? 1 : 0,
      'difficulty': item.difficulty,
      'started_at': _formatDate(item.startedAt),
      'finished_at': _formatDate(item.finishedAt),
      'library_id': item.libraryId,
      'library_due_at': _formatDate(item.libraryDueAt),
      'platform_name': item.platformName,
      'discovery_source': item.discoverySource,
      'created_at': item.createdAt.toIso8601String(),
      'updated_at': item.updatedAt.toIso8601String(),
      'is_dirty': 0,
      'client_request_id': item.clientRequestId,
      'create_thumbnail_path': item.createThumbnailPath,
    };
  }

  BookItem _rowToBookItem(Map<String, dynamic> row, List<BookTag> tags) {
    return BookItem(
      userBookId: row['user_book_id'] as int,
      serverId: row['server_id'] as int?,
      clientRequestId: row['client_request_id'] as String?,
      createThumbnailPath: row['create_thumbnail_path'] as String?,
      bookId: row['book_id'] as int?,
      isbn13: row['isbn13'] as String?,
      title: row['title'] as String,
      author: row['author'] as String?,
      publisher: row['publisher'] as String?,
      statsTotalPages: row['stats_total_pages'] as int?,
      displayTotalPages: row['display_total_pages'] as int?,
      coverImageUrl: row['cover_image_url'] as String?,
      displayCategoryId: row['display_category_id'] as int?,
      category: row['category'] as String?,
      status: BookStatus.fromApiValue(row['status'] as String),
      currentPage: row['current_page'] as int,
      myRating: (row['my_rating'] as num?)?.toDouble(),
      shortReview: row['short_review'] as String?,
      isMasterpiece: (row['is_masterpiece'] as int) == 1,
      sourceType: row['source_type'] as String?,
      rereadCount: row['reread_count'] as int,
      wantToReread: (row['want_to_reread'] as int? ?? 0) == 1,
      difficulty: row['difficulty'] as String?,
      startedAt: _parseDate(row['started_at'] as String?),
      finishedAt: _parseDate(row['finished_at'] as String?),
      libraryId: row['library_id'] as int?,
      libraryDueAt: _parseDate(row['library_due_at'] as String?),
      platformName: row['platform_name'] as String?,
      discoverySource: row['discovery_source'] as String?,
      tags: tags,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  String? _formatDate(DateTime? date) =>
      date?.toIso8601String().substring(0, 10);

  DateTime? _parseDate(String? value) =>
      value == null ? null : DateTime.parse(value);

  // ---------------------------------------------------------------------
  // 로컬 → 서버 저장 모드 재전환 Import 전용
  // ---------------------------------------------------------------------

  /// Import 전 멱등 키를 한 번 발급해 로컬 DB에 고정한다
  /// ([BookItem.clientRequestId]가 없는 행 — 서버 동기화로만 내려온 옛
  /// 데이터 등). api-doc(items) 기준 이 키는 "최초 Import 전에 생성해 로컬
  /// DB에 고정 저장"해야 하므로, 이미 값이 있는 행은 건드리지 않는다.
  Future<void> ensureClientRequestIds() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'user_book',
      columns: ['user_book_id'],
      where: 'client_request_id IS NULL',
    );
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      for (final row in rows) {
        await txn.update(
          'user_book',
          {'client_request_id': const Uuid().v4()},
          where: 'user_book_id = ?',
          whereArgs: [row['user_book_id']],
        );
      }
    });
  }

  /// Import `/complete` 성공 후 서버 ID를 확정하고 dirty를 해제한다.
  ///
  /// 로컬 저장 모드에서 만든 책은 [insertLocalCreate]가 항상 `is_dirty = 1`로
  /// 남겨 둔다(로컬 모드는 서버로 push하지 않는다). 여기서 풀지 않으면 서버
  /// 모드로 돌아간 뒤 평소 동기화가 "아직 push 못한 로컬 생성"으로 오인해
  /// 이미 Import로 서버에 만든 책을 다시 만들려고 시도한다.
  ///
  /// 매핑은 `/complete`가 성공한 뒤에만 반영한다 — 청크 응답을 받는 즉시
  /// 반영하면, 이후 청크나 attachments·complete가 실패해 서버가 세션
  /// 전체를 정리했을 때 로컬에는 더 이상 존재하지 않는 서버 행의 ID가 남아,
  /// 다음 전체 동기화([reconcile])가 "서버에서 사라진 정상 행"으로 오인해
  /// 로컬 원본까지 지워버릴 수 있다.
  ///
  /// `synced_updated_at`은 일부러 null로 남긴다 — `/items` 응답은 서버
  /// ID만 줄 뿐 Import로 생성·복구된 행의 실제 서버 `updated_at`은 내려주지
  /// 않는다. 여기서 로컬(과거) `updated_at`을 대신 채우면, 전환 직후 첫
  /// 책 정보 PATCH가 그 값을 충돌 검사 기준으로 보내는데 서버의 실제
  /// `updated_at`(Import 시각)과 달라 409가 나고 사용자의 첫 수정이
  /// 반영되지 않는다. null이면 [BookRecordApi.patchBookInfo]가 `updatedAt`
  /// 필드 자체를 생략해 그 검사를 건너뛴다.
  ///
  /// [executor]는 다른 도메인(노트·독후감·태그)의 같은 이름 메서드와 하나의
  /// 트랜잭션을 공유하기 위한 것이다(`ServerStorageMigrationRepositorySteps.applyResults`)
  /// — 네 테이블 중 일부만 반영된 채 중간에 실패하는 상태를 줄인다.
  Future<void> applyImportResults(
    DatabaseExecutor executor,
    Map<int, int> serverIdByLocalId,
  ) async {
    for (final entry in serverIdByLocalId.entries) {
      await executor.update(
        'user_book',
        {
          'server_id': entry.value,
          'is_dirty': 0,
          'dirty_fields': null,
          'synced_updated_at': null,
        },
        where: 'user_book_id = ?',
        whereArgs: [entry.key],
      );
    }
  }

  Future<int> _nextLocalUserBookId(Transaction txn) async {
    final rows = await txn.rawQuery(
      'SELECT MIN(user_book_id) AS min_id FROM user_book',
    );
    final current = rows.single['min_id'] as int?;
    return current != null && current <= 0 ? current - 1 : -1;
  }
}
