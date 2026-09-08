import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../bookshelf/data/bookshelf_database.dart';
import '../../record_sync/models/record_sync_payload.dart';
import '../models/book_note.dart';

/// 노트/메모 로컬 DB 쿼리/쓰기 전담.
///
/// `book_note`/`book_note_memo`의 `id`는 로컬 PK로, 오프라인 생성 시
/// [_nextLocalId]가 부여하는 음수 임시값일 수 있다. 서버에 반영된 뒤에는
/// `server_id`에 서버가 내려준 진짜 ID를 채우되 `id`는 절대 바꾸지 않는다
/// (이유는 `BookshelfDatabase._createRecordTables` 참고). `is_dirty = 1`인
/// 행은 [reconcileFullNotes]/[applyNoteChanges](서버 조회 반영) 모두 덮어쓰거나
/// 삭제하지 않는다 — 아직 push되지 못한 로컬 우선 편집을 지키기 위함이다.
class BookNoteDao {
  const BookNoteDao();

  /// 완독 책에 연결된 메모 총 개수(독서 통계 화면의 "메모" 카드,
  /// `stats-screen.md` §1-3). [year]를 지정하면 그 해 완독한 책으로 범위를
  /// 좁힌다(`finished_at`의 앞 4자리, `bookshelf_dao.dart`가 저장하는
  /// `YYYY-MM-DD` 포맷 기준). `user_book_id IN (...)` 목록을 직접 바인딩하지
  /// 않고 `user_book`을 조인하는 이유는 SQLite의 바인딩 파라미터 개수 제한
  /// (기본 999개)에 걸리지 않기 위해서다 — 완독 책이 많은 사용자도 안전하다.
  Future<int> countMemosForFinishedBooks({
    required int ownerUserId,
    required String finishedStatusApiValue,
    int? year,
  }) async {
    final db = await BookshelfDatabase.instance();
    final where = <String>[
      'n.owner_user_id = ?',
      'n.deleted_at IS NULL',
      'm.deleted_at IS NULL',
      'b.status = ?',
    ];
    final args = <Object?>[ownerUserId, finishedStatusApiValue];
    if (year != null) {
      where.add("substr(b.finished_at, 1, 4) = ?");
      args.add(year.toString());
    }
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS memo_count
      FROM book_note_memo m
      JOIN book_note n ON n.id = m.note_id
      JOIN user_book b ON b.user_book_id = n.user_book_id
      WHERE ${where.join(' AND ')}
      ''', args);
    return (rows.single['memo_count'] as int?) ?? 0;
  }

  Future<List<BookNoteSummary>> findByUserBook({
    required int ownerUserId,
    required int userBookId,
  }) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.rawQuery(
      '''
      SELECT n.*,
             COUNT(m.id) AS memo_count,
             MIN(COALESCE(m.start_page, m.end_page)) AS first_page,
             MAX(COALESCE(m.end_page, m.start_page)) AS last_page
      FROM book_note n
      LEFT JOIN book_note_memo m
        ON m.note_id = n.id AND m.deleted_at IS NULL
      WHERE n.owner_user_id = ?
        AND n.user_book_id = ?
        AND n.deleted_at IS NULL
      GROUP BY n.id
      ORDER BY n.updated_at DESC, n.id DESC
      ''',
      [ownerUserId, userBookId],
    );
    return rows
        .map(
          (row) => BookNoteSummary(
            note: _noteFromRow(row),
            memoCount: (row['memo_count'] as int?) ?? 0,
            firstPage: row['first_page'] as int?,
            lastPage: row['last_page'] as int?,
          ),
        )
        .toList(growable: false);
  }

  Future<BookNoteDetail?> findDetail({
    required int ownerUserId,
    required int userBookId,
    required int noteId,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final noteRows = await txn.query(
        'book_note',
        where:
            'id = ? AND owner_user_id = ? AND user_book_id = ? '
            'AND deleted_at IS NULL',
        whereArgs: [noteId, ownerUserId, userBookId],
        limit: 1,
      );
      if (noteRows.isEmpty) return null;

      final memoRows = await txn.query(
        'book_note_memo',
        where: 'note_id = ? AND deleted_at IS NULL',
        whereArgs: [noteId],
        orderBy: 'created_at ASC, sort_order ASC, id ASC',
      );
      return BookNoteDetail(
        note: _noteFromRow(noteRows.single),
        memos: memoRows.map(_memoFromRow).toList(growable: false),
      );
    });
  }

  Future<BookNote> createNote({
    required int ownerUserId,
    required int userBookId,
    required String? title,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final id = await _nextLocalId(txn, 'book_note');
      final now = DateTime.now().toUtc().toIso8601String();
      final values = <String, Object?>{
        'id': id,
        'server_id': null,
        'owner_user_id': ownerUserId,
        'user_book_id': userBookId,
        'title': title,
        'deleted_at': null,
        'created_at': now,
        'updated_at': now,
        'is_dirty': 1,
      };
      await txn.insert('book_note', values);
      return _noteFromRow(values);
    });
  }

  Future<BookNote> updateTitle({
    required int ownerUserId,
    required int userBookId,
    required int noteId,
    required String? title,
  }) async {
    final db = await BookshelfDatabase.instance();
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await db.update(
      'book_note',
      {'title': title, 'updated_at': now, 'is_dirty': 1},
      where:
          'id = ? AND owner_user_id = ? AND user_book_id = ? '
          'AND deleted_at IS NULL',
      whereArgs: [noteId, ownerUserId, userBookId],
    );
    if (count != 1) throw StateError('Note not found');

    final rows = await db.query(
      'book_note',
      where: 'id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    return _noteFromRow(rows.single);
  }

  /// [localImagePath]는 `noteMemoImageStore`에 복사해 둔 사진의 상대
  /// 경로다(사진이 없으면 null). 새로 만든 사진은 아직 서버에 없으므로
  /// `image_url`은 항상 null로 시작한다 — 그 상태가 곧 "업로드 필요"
  /// 표식이다([BookNoteRepository]의 push 참고).
  Future<BookNoteMemo> createNoteMemo({
    required int ownerUserId,
    required int userBookId,
    required int noteId,
    required BookNoteMemoDraft draft,
    required String? localImagePath,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      await _requireActiveNote(
        txn,
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        noteId: noteId,
      );
      final id = await _nextLocalId(txn, 'book_note_memo');
      final orderRows = await txn.rawQuery(
        'SELECT MAX(sort_order) AS max_order FROM book_note_memo '
        'WHERE note_id = ? AND deleted_at IS NULL',
        [noteId],
      );
      final maxOrder = orderRows.single['max_order'] as int?;
      final now = DateTime.now().toUtc().toIso8601String();
      final values = <String, Object?>{
        'id': id,
        'server_id': null,
        // 네트워크 push가 아니라 로컬 신규 생성 트랜잭션에서 한 번만
        // 발급한다. 이후 재시도는 이 컬럼을 다시 읽어 같은 값을 사용한다.
        'client_request_id': const Uuid().v4(),
        'note_id': noteId,
        'memo_type': draft.type.dbValue,
        'start_page': draft.startPage,
        'end_page': draft.endPage,
        'content': draft.content,
        'image_url': null,
        'local_image_path': localImagePath,
        'is_important': draft.isImportant ? 1 : 0,
        'sort_order': (maxOrder ?? -1) + 1,
        'deleted_at': null,
        'created_at': now,
        'updated_at': now,
        'is_dirty': 1,
      };
      await txn.insert('book_note_memo', values);
      return _memoFromRow(values);
    });
  }

  /// 사진 컬럼은 [BookNoteMemoDraft.imageChange]가 요구할 때만 건드린다 —
  /// `unchanged`면 두 컬럼 모두 update 문에 넣지 않아 기존 값(서버 URL과
  /// 로컬 사본 경로)이 그대로 유지된다. `replaced`면 새 로컬 사본을 넣고
  /// `image_url`을 비워 "다시 업로드해야 함"으로 되돌린다.
  Future<BookNoteMemo> updateNoteMemo({
    required int ownerUserId,
    required int userBookId,
    required int noteId,
    required int noteMemoId,
    required BookNoteMemoDraft draft,
    required String? localImagePath,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      await _requireActiveNote(
        txn,
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        noteId: noteId,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      final count = await txn.update(
        'book_note_memo',
        {
          'memo_type': draft.type.dbValue,
          'start_page': draft.startPage,
          'end_page': draft.endPage,
          'content': draft.content,
          if (draft.imageChange == MemoImageChange.replaced) ...{
            'image_url': null,
            'local_image_path': localImagePath,
          },
          if (draft.imageChange == MemoImageChange.cleared) ...{
            'image_url': null,
            'local_image_path': null,
          },
          'is_important': draft.isImportant ? 1 : 0,
          'updated_at': now,
          'is_dirty': 1,
        },
        where: 'id = ? AND note_id = ? AND deleted_at IS NULL',
        whereArgs: [noteMemoId, noteId],
      );
      if (count != 1) throw StateError('Note memo not found');
      final rows = await txn.query(
        'book_note_memo',
        where: 'id = ?',
        whereArgs: [noteMemoId],
        limit: 1,
      );
      return _memoFromRow(rows.single);
    });
  }

  Future<DeleteNoteMemoResult> deleteNoteMemo({
    required int ownerUserId,
    required int userBookId,
    required int noteId,
    required int noteMemoId,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      await _requireActiveNote(
        txn,
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        noteId: noteId,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      final count = await txn.update(
        'book_note_memo',
        {'deleted_at': now, 'updated_at': now, 'is_dirty': 1},
        where: 'id = ? AND note_id = ? AND deleted_at IS NULL',
        whereArgs: [noteMemoId, noteId],
      );
      if (count != 1) throw StateError('Note memo not found');

      final remainingRows = await txn.rawQuery(
        'SELECT COUNT(*) AS memo_count FROM book_note_memo '
        'WHERE note_id = ? AND deleted_at IS NULL',
        [noteId],
      );
      final hasRemaining = (remainingRows.single['memo_count'] as int) > 0;
      if (!hasRemaining) {
        await txn.update(
          'book_note',
          {'deleted_at': now, 'updated_at': now, 'is_dirty': 1},
          where: 'id = ?',
          whereArgs: [noteId],
        );
      }
      return DeleteNoteMemoResult(noteWasDeleted: !hasRemaining);
    });
  }

  /// 노트 자체를 소프트 삭제한다. 메모는 건드리지 않는다 — 부모 노트가
  /// `deleted_at IS NOT NULL`이 되는 순간 [findByUserBook]/[findDetail]
  /// 모두 이 노트를 더 이상 보여주지 않으므로 화면상으로는 메모까지 함께
  /// 사라진 것과 같고, 실제 서버 반영은 push 시점에 노트 전용 삭제 API
  /// 한 번으로 메모까지 함께 처리된다([BookNoteRepository]의 push 로직
  /// 참고).
  Future<void> deleteNote({
    required int ownerUserId,
    required int userBookId,
    required int noteId,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await _requireActiveNote(
        txn,
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        noteId: noteId,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        'book_note',
        {'deleted_at': now, 'updated_at': now, 'is_dirty': 1},
        where: 'id = ?',
        whereArgs: [noteId],
      );
    });
  }

  /// 노트 삭제 push([BookNoteRepository._pushDeletedNote])가 정리할 이미지를
  /// 판단하기 위해, 삭제 여부와 상관없이 그 노트에 딸린 메모 전부를 반환한다.
  Future<List<BookNoteMemo>> getAllMemosForNote(int noteLocalId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_note_memo',
      where: 'note_id = ?',
      whereArgs: [noteLocalId],
    );
    return rows.map(_memoFromRow).toList(growable: false);
  }

  /// 삭제 push가 끝난(또는 애초에 서버에 없던) 노트와 그 메모 전부를
  /// 로컬에서 물리 삭제한다.
  Future<void> purgeNoteAndMemos(int noteLocalId) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await txn.delete(
        'book_note_memo',
        where: 'note_id = ?',
        whereArgs: [noteLocalId],
      );
      await txn.delete('book_note', where: 'id = ?', whereArgs: [noteLocalId]);
    });
  }

  // ---------------------------------------------------------------------
  // 서버 동기화(dirty push) 전용
  // ---------------------------------------------------------------------

  Future<DateTime?> getLastSyncedAtNote() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['last_synced_at_note'],
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['value'] as String);
  }

  /// 제목 편집 등으로 dirty가 된(is_dirty=1) 노트의 로컬 ID 목록.
  Future<List<int>> getDirtyNoteLocalIds() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_note',
      columns: ['id'],
      where: 'is_dirty = 1',
    );
    return rows.map((r) => r['id'] as int).toList(growable: false);
  }

  /// dirty(is_dirty=1) 메모가 하나라도 있는 노트의 로컬 ID 목록(중복 제거).
  Future<List<int>> getNoteIdsWithDirtyMemos() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.rawQuery(
      'SELECT DISTINCT note_id FROM book_note_memo WHERE is_dirty = 1',
    );
    return rows.map((r) => r['note_id'] as int).toList(growable: false);
  }

  Future<BookNote?> getNoteByLocalId(int localId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_note',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    return rows.isEmpty ? null : _noteFromRow(rows.single);
  }

  /// 특정 노트에 속한 dirty 메모(생성/수정/삭제 대기 중) 전체. 소프트
  /// 삭제된(`deleted_at != null`) 메모도 포함한다 — push 쪽에서 삭제
  /// 요청으로 처리해야 하므로.
  ///
  /// `created_at ASC`로 정렬한다 — `id ASC`를 쓰면 로컬 전용 메모의 음수
  /// ID가 생성 순서와 거꾸로(가장 최근 것이 가장 작은 음수) 정렬돼, 제목
  /// 없는 신규 노트를 만들 때 가장 나중에 추가한 메모가 먼저 push되며 노트를
  /// 만들어버리고, 서버 `sortOrder`("마지막 순서 다음 값")도 로컬 표시
  /// 순서와 반대로 매겨진다.
  Future<List<BookNoteMemo>> getDirtyMemosForNote(int noteLocalId) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_note_memo',
      where: 'note_id = ? AND is_dirty = 1',
      whereArgs: [noteLocalId],
      orderBy: 'created_at ASC, id DESC',
    );
    return rows.map(_memoFromRow).toList(growable: false);
  }

  /// 이미 서버에 존재하던 노트(`server_id != null`)의 제목 push가 성공한 뒤
  /// 호출한다. push 요청을 만들 때 읽은 [capturedUpdatedAt]과 현재 로컬
  /// `updated_at`이 같을 때만(그 사이 새 로컬 편집이 없었을 때만) dirty를
  /// 해제한다 — 네트워크가 오가는 동안 사용자가 제목을 또 수정했다면 그
  /// 편집은 아직 반영되지 않았으므로 dirty를 유지해 다음 push가 최신 내용을
  /// 다시 보내게 한다.
  Future<void> confirmNoteTitlePush({
    required int localId,
    required DateTime capturedUpdatedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'book_note',
        columns: ['updated_at'],
        where: 'id = ?',
        whereArgs: [localId],
      );
      if (rows.isEmpty) return;
      final current = DateTime.parse(rows.single['updated_at'] as String);
      if (!current.isAtSameMomentAs(capturedUpdatedAt)) return;
      await txn.update(
        'book_note',
        {'is_dirty': 0},
        where: 'id = ?',
        whereArgs: [localId],
      );
    });
  }

  /// 로컬 전용(`server_id IS NULL`) 노트가 제목 PUT으로 서버에 처음
  /// 생성된 뒤 호출한다. `server_id`는(신원 확정이므로) 항상 채우고, dirty
  /// 해제는 [confirmNoteTitlePush]와 동일하게 그 사이 새 편집이 없었을
  /// 때만 한다.
  Future<void> confirmNoteCreated({
    required int localId,
    required int serverId,
    required DateTime capturedUpdatedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'book_note',
        columns: ['updated_at'],
        where: 'id = ?',
        whereArgs: [localId],
      );
      if (rows.isEmpty) return;
      final current = DateTime.parse(rows.single['updated_at'] as String);
      final unchanged = current.isAtSameMomentAs(capturedUpdatedAt);
      await txn.update(
        'book_note',
        {'server_id': serverId, if (unchanged) 'is_dirty': 0},
        where: 'id = ?',
        whereArgs: [localId],
      );
    });
  }

  /// 메모 생성/수정 push가 성공한 뒤 서버 응답으로 확정 반영한다. `server_id`는
  /// 항상 채우고(신원 확정), 필드 값은 push 요청을 만들 때 읽은
  /// [capturedUpdatedAt]과 현재 로컬 `updated_at`이 같을 때만(그 사이 새
  /// 로컬 편집이 없었을 때만) 서버 응답으로 덮어써 dirty를 해제한다 — 그
  /// 렇지 않으면 아직 반영되지 않은 최신 로컬 편집을 이전 push의 응답으로
  /// 되돌리게 된다.
  ///
  /// 반환값은 필드 값까지 실제로 반영됐는지 여부(위 "unchanged" 조건). 호출
  /// 쪽(`BookNoteRepository._confirmMemoAndCleanupImage`)이 이 값을 보고
  /// `image_url`이 실제로 새 원격 URL로 바뀌었는지 판단해야, DB가 여전히
  /// 옛 로컬 사진 경로를 참조하는데 그 파일을 지워버리는 사고를 막는다.
  Future<bool> confirmNoteMemoSynced({
    required int localId,
    required int serverId,
    required DateTime capturedUpdatedAt,
    required BookNoteMemoType memoType,
    required int? startPage,
    required int? endPage,
    required String? content,
    required String? imageUrl,
    required bool isImportant,
    required int sortOrder,
  }) async {
    final db = await BookshelfDatabase.instance();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'book_note_memo',
        columns: ['updated_at'],
        where: 'id = ?',
        whereArgs: [localId],
      );
      if (rows.isEmpty) return false;
      final storedUpdatedAt = rows.single['updated_at'] as String?;
      final current = storedUpdatedAt == null
          ? null
          : DateTime.parse(storedUpdatedAt);
      final unchanged =
          current != null && current.isAtSameMomentAs(capturedUpdatedAt);
      if (unchanged) {
        await txn.update(
          'book_note_memo',
          {
            'server_id': serverId,
            'memo_type': memoType.dbValue,
            'start_page': startPage,
            'end_page': endPage,
            'content': content,
            'image_url': imageUrl,
            'is_important': isImportant ? 1 : 0,
            'sort_order': sortOrder,
            'is_dirty': 0,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      } else {
        await txn.update(
          'book_note_memo',
          {'server_id': serverId},
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
      return unchanged;
    });
  }

  /// 삭제 push(또는 애초에 서버에 없던 로컬 전용 메모의 정리)가 끝난 메모를
  /// 로컬에서 물리 삭제한다.
  Future<void> purgeMemo(int localId) async {
    final db = await BookshelfDatabase.instance();
    await db.delete('book_note_memo', where: 'id = ?', whereArgs: [localId]);
  }

  // ---------------------------------------------------------------------
  // 로컬 사진(local_image_path) 전용
  // ---------------------------------------------------------------------

  /// 서버 사진은 있는데 로컬 사본이 없는 PHOTO 메모(내려받기 대상).
  ///
  /// [noteId]를 주면 그 노트의 사진만 돌려준다 — 화면 진입 시점에 필요한
  /// 사진만 받는 경로([BookNoteRepository.ensureImagesForNote])가 쓴다.
  /// 생략하면 계정 전체가 대상이며, 로컬 저장 모드 전환 전에 모든 사진을
  /// 확보할 때 쓴다.
  ///
  /// [excludeImageUrls]는 서버가 더 이상 주지 않는다고 확인된 사진이다.
  /// 제외하지 않으면 화면에 들어올 때마다 같은 실패를 되풀이한다.
  Future<List<BookNoteMemo>> findPhotoMemosMissingLocalImage({
    int? noteId,
    List<String> excludeImageUrls = const [],
  }) async {
    final db = await BookshelfDatabase.instance();
    final excludeClause = excludeImageUrls.isEmpty
        ? ''
        : ' AND image_url NOT IN '
              '(${List.filled(excludeImageUrls.length, '?').join(', ')})';
    final whereArgs = <Object?>[?noteId, ...excludeImageUrls];
    final rows = await db.query(
      'book_note_memo',
      where:
          "memo_type = 'PHOTO' AND deleted_at IS NULL "
          'AND image_url IS NOT NULL AND local_image_path IS NULL'
          '${noteId == null ? '' : ' AND note_id = ?'}'
          '$excludeClause',
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'updated_at DESC, id DESC',
    );
    return rows.map(_memoFromRow).toList(growable: false);
  }

  /// 아직 로컬 사본과 연결되지 않은 PHOTO 메모의 서버 사진 URL 전체.
  /// orphan 정리가 "이미 내려받았지만 아직 연결되지 못한 사본"까지 지우지
  /// 않도록 지켜야 할 목록이다.
  Future<List<String>> getPendingPhotoImageUrls() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_note_memo',
      columns: ['image_url'],
      where:
          "memo_type = 'PHOTO' AND deleted_at IS NULL "
          'AND image_url IS NOT NULL AND local_image_path IS NULL',
    );
    return rows
        .map((row) => row['image_url'] as String)
        .toList(growable: false);
  }

  /// DB가 참조 중인 모든 로컬 사진 경로(삭제 대기 중인 메모 포함). 참조되지
  /// 않는 파일을 지우는 orphan 정리의 기준 목록이다 — 소프트 삭제된 메모도
  /// 포함해야 아직 push되지 않은 사진을 실수로 지우지 않는다.
  Future<List<String>> getAllLocalImagePaths() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_note_memo',
      columns: ['local_image_path'],
      where: 'local_image_path IS NOT NULL',
    );
    return rows
        .map((row) => row['local_image_path'] as String)
        .toList(growable: false);
  }

  /// 파일이 실제로는 사라진 로컬 사본 참조를 끊는다. 다음 hydration이
  /// 서버 URL로 다시 내려받는다.
  Future<void> clearLocalImagePaths(List<String> localImagePaths) async {
    if (localImagePaths.isEmpty) return;
    final db = await BookshelfDatabase.instance();
    final placeholders = List.filled(localImagePaths.length, '?').join(', ');
    await db.update(
      'book_note_memo',
      {'local_image_path': null},
      where: 'local_image_path IN ($placeholders)',
      whereArgs: localImagePaths,
    );
  }

  /// 내려받은 사본을 메모에 연결한다. 내려받는 동안 그 메모의 사진이
  /// 바뀌었을 수 있으므로([expectedImageUrl]과 다르면) 그때는 반영하지
  /// 않는다 — 엉뚱한 사진을 로컬 우선 표시로 고정해 버리지 않기 위함이다.
  Future<void> setLocalImagePath({
    required int localId,
    required String localImagePath,
    required String expectedImageUrl,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.update(
      'book_note_memo',
      {'local_image_path': localImagePath},
      where: 'id = ? AND image_url = ?',
      whereArgs: [localId, expectedImageUrl],
    );
  }

  /// 서버 사진이 "같은 사진"인지 비교한다. 호스트나 쿼리 문자열(서명/만료
  /// 등)이 달라져도 경로가 같으면 같은 사진으로 본다 — 그러지 않으면
  /// 동기화 때마다 교체로 오인해 로컬 사본을 지우고 다시 받는다.
  static bool _isSameImage(String? a, String? b) {
    if (a == null || b == null) return a == b;
    return _imageIdentityOf(a) == _imageIdentityOf(b);
  }

  static String _imageIdentityOf(String url) => Uri.tryParse(url)?.path ?? url;

  /// `/api/me/records` 전체 조회 결과로 노트/메모 테이블을 맞춘다: 서버에
  /// 있는 행은 upsert, 서버에 없는(로컬에만 남은) 비-dirty 행은 삭제. dirty
  /// 행(및 dirty 메모가 하나라도 남은 노트)은 건드리지 않는다.
  ///
  /// [activeUserBookIds]는 같은 `/api/me/records` 응답의 `books` 배열이다.
  /// 이 API는 "소프트 삭제된 책장 항목의 데이터는 포함하지 않는다"(api-doc)
  /// — 즉 책이 서재에서 삭제되면 그 책의 노트/메모도 이번 응답의 [notes]/
  /// [noteMemos]에서 통째로 빠진다. 이를 "서버에서 삭제됨"으로 오인해 지우면
  /// 아직 서재 삭제 자체는 동기화되지 않은(또는 영구 보관되는) 노트 데이터를
  /// 잃는다. 그래서 "노트/메모가 없다"만으로 삭제하지 않고, 그 노트의
  /// `user_book_id`가 이번 응답에 실제로 존재하는 책일 때만(=책은 그대로
  /// 있는데 노트만 없어졌을 때만) 삭제 대상으로 본다.
  ///
  /// [requestedAt]은 이 전체 동기화 요청을 보내기 *직전* 시각(UTC)이어야
  /// 한다 — 응답을 받은 뒤 시각을 쓰면 그 사이 서버에 반영된 변경이 다음
  /// 증분 동기화의 since보다 앞서게 되어 영구히 누락될 수 있다.
  Future<void> reconcileFullNotes({
    required int ownerUserId,
    required List<int> activeUserBookIds,
    required List<ServerBookNote> notes,
    required List<ServerBookNoteMemo> noteMemos,
    required DateTime requestedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      final localActiveUserBookIds = await _localUserBookIdsForServerIds(
        txn,
        activeUserBookIds,
      );
      for (final note in notes) {
        await _upsertServerNoteTxn(txn, ownerUserId, note);
      }
      for (final memo in noteMemos) {
        final localNoteId = await _findLocalNoteIdByServerId(txn, memo.noteId);
        if (localNoteId == null) {
          // 전체 조회 응답은 notes/noteMemos가 FK로 일관되어야 한다
          // (record_sync의 RecordSyncPayload._validateRelationships와 같은
          // 보장) — 그런데도 로컬에서 부모를 못 찾으면 이 메모는 이번
          // 전체 동기화로 복구할 수 없다는 뜻이므로 조용히 버리지 않고
          // 로그만 남긴다.
          developer.log(
            '[노트 전체 동기화] result=SKIP reason=orphan_memo '
            'serverMemoId=${memo.id} serverNoteId=${memo.noteId}',
          );
          continue;
        }
        await _upsertServerMemoTxn(txn, localNoteId, memo);
      }

      // 메모 삭제를 노트 삭제보다 먼저 실행한다. 순서를 반대로 하면(노트
      // 삭제 먼저) 응답에 없는(=서버에서 사라진) 노트가 이 시점에 이미
      // CASCADE로 자기 메모까지 함께 지워버려서, "노트는 그대로인데 메모
      // 하나만 삭제 보관 기간(30일)을 넘겨 deletedNoteMemoIds에도 더 이상
      // 안 잡히는" 케이스를 이 아래 메모 삭제 쿼리가 더 이상 볼 수 없게
      // 된다(그때는 이미 그 노트 밑에 남은 메모가 서버 응답과 항상
      // 일치하므로 "없는 메모" 자체가 안 잡힘) — 바로 이 케이스가 전체
      // 동기화가 존재하는 이유이므로 먼저 처리해야 한다.
      final serverMemoIds = noteMemos.map((m) => m.id).toList(growable: false);
      await _deleteMissingMemosTxn(
        txn,
        ownerUserId,
        localActiveUserBookIds,
        serverMemoIds,
      );

      final serverNoteIds = notes.map((n) => n.id).toList(growable: false);
      await _deleteMissingNotesTxn(
        txn,
        ownerUserId,
        localActiveUserBookIds,
        serverNoteIds,
      );

      await txn.insert('sync_meta', {
        'key': 'last_synced_at_note',
        'value': requestedAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// `/api/me/notes/sync/changes` 증분 동기화 결과를 반영한다. dirty 행은
  /// [reconcileFullNotes]와 동일하게 보호한다. 변경이 없어도 매번
  /// `last_synced_at_note`를 앞으로 당긴다(다음 요청이 갈수록 넓어지는
  /// 구간을 다시 스캔하지 않도록) — 단, 부모 노트를 로컬에서 찾지 못한
  /// 메모(orphan)가 하나라도 있었으면 그 메모는 이번 반영에서 영구히
  /// 유실되므로 기준값을 앞으로 당기지 않고 아예 지운다. 그러면 다음
  /// [BookNoteRepository.sync] 호출이 `since == null`로 판단해 전체
  /// 동기화(`/api/me/records`)로 대체되어 놓친 메모를 되찾는다 — 같은
  /// since로 증분을 다시 시도해 봤자 서버는 같은(이미 유실 처리된) 응답을
  /// 되풀이할 뿐이라 증분 재시도로는 복구되지 않는다.
  Future<void> applyNoteChanges({
    required int ownerUserId,
    required List<ServerBookNote> upsertedNotes,
    required List<int> deletedNoteIds,
    required List<ServerBookNoteMemo> upsertedNoteMemos,
    required List<int> deletedNoteMemoIds,
    required DateTime syncedAt,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      for (final note in upsertedNotes) {
        // 증분 응답에는 owner_user_id가 내려오지 않는다(API가 이미 로그인
        // 사용자 소유 노트만 반환하므로). book_note.owner_user_id는 서버
        // 응답 필드가 아닌 로컬 계정 격리용 값이라, 신규 삽입 시 호출자가
        // 넘긴 현재 세션 사용자 ID로 채운다.
        await _upsertServerNoteTxn(txn, ownerUserId, note);
      }
      var hasOrphanMemo = false;
      for (final memo in upsertedNoteMemos) {
        final localNoteId = await _findLocalNoteIdByServerId(txn, memo.noteId);
        if (localNoteId == null) {
          hasOrphanMemo = true;
          developer.log(
            '[노트 증분 동기화] result=SKIP reason=orphan_memo '
            'serverMemoId=${memo.id} serverNoteId=${memo.noteId}',
          );
          continue;
        }
        await _upsertServerMemoTxn(txn, localNoteId, memo);
      }

      if (deletedNoteIds.isNotEmpty) {
        final placeholders = List.filled(deletedNoteIds.length, '?').join(', ');
        await txn.delete(
          'book_note',
          where:
              'server_id IN ($placeholders) AND is_dirty = 0 '
              'AND NOT EXISTS (SELECT 1 FROM book_note_memo '
              'WHERE note_id = book_note.id AND is_dirty = 1)',
          whereArgs: deletedNoteIds,
        );
      }
      if (deletedNoteMemoIds.isNotEmpty) {
        final placeholders = List.filled(
          deletedNoteMemoIds.length,
          '?',
        ).join(', ');
        await txn.delete(
          'book_note_memo',
          where: 'server_id IN ($placeholders) AND is_dirty = 0',
          whereArgs: deletedNoteMemoIds,
        );
      }

      if (hasOrphanMemo) {
        await txn.delete(
          'sync_meta',
          where: 'key = ?',
          whereArgs: ['last_synced_at_note'],
        );
      } else {
        await txn.insert('sync_meta', {
          'key': 'last_synced_at_note',
          'value': syncedAt.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<int> _upsertServerNoteTxn(
    Transaction txn,
    int ownerUserId,
    ServerBookNote note,
  ) async {
    final localUserBookId =
        await _findLocalUserBookIdByServerId(txn, note.userBookId) ??
        note.userBookId;
    final existing = await txn.query(
      'book_note',
      columns: ['id', 'is_dirty'],
      where: 'server_id = ?',
      whereArgs: [note.id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final localId = existing.single['id'] as int;
      final isDirty = existing.single['is_dirty'] == 1;
      if (!isDirty) {
        await txn.update(
          'book_note',
          {
            'title': note.title,
            'user_book_id': localUserBookId,
            'deleted_at': null,
            'updated_at': note.updatedAt.toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
      return localId;
    }
    await txn.insert('book_note', {
      'id': note.id,
      'server_id': note.id,
      'owner_user_id': ownerUserId,
      'user_book_id': localUserBookId,
      'title': note.title,
      'deleted_at': null,
      'created_at': note.createdAt.toUtc().toIso8601String(),
      'updated_at': note.updatedAt.toUtc().toIso8601String(),
      'is_dirty': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return note.id;
  }

  /// 서버 응답으로 메모를 반영한다. 로컬 사본 경로(`local_image_path`)는
  /// 서버가 모르는 값이므로 그대로 보존하되, 서버 사진 자체가 바뀌었으면
  /// (다른 기기에서 사진 교체) 옛 사본은 더 이상 이 메모의 사진이 아니므로
  /// 비운다 — 파일 정리는 [BookNoteRepository]의 orphan 정리가 맡는다.
  Future<void> _upsertServerMemoTxn(
    Transaction txn,
    int localNoteId,
    ServerBookNoteMemo memo,
  ) async {
    final existing = await txn.query(
      'book_note_memo',
      columns: ['id', 'is_dirty', 'image_url'],
      where: 'server_id = ?',
      whereArgs: [memo.id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final localId = existing.single['id'] as int;
      final isDirty = existing.single['is_dirty'] == 1;
      if (!isDirty) {
        final storedImageUrl = existing.single['image_url'] as String?;
        final imageReplaced = !_isSameImage(storedImageUrl, memo.imageUrl);
        await txn.update(
          'book_note_memo',
          {
            'note_id': localNoteId,
            'memo_type': memo.memoType,
            'start_page': memo.startPage,
            'end_page': memo.endPage,
            'content': memo.content,
            'image_url': memo.imageUrl,
            if (imageReplaced) 'local_image_path': null,
            'is_important': memo.isImportant ? 1 : 0,
            'sort_order': memo.sortOrder,
            'deleted_at': null,
            'updated_at': memo.updatedAt.toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
      return;
    }
    await txn.insert('book_note_memo', {
      'id': memo.id,
      'server_id': memo.id,
      'note_id': localNoteId,
      'memo_type': memo.memoType,
      'start_page': memo.startPage,
      'end_page': memo.endPage,
      'content': memo.content,
      'image_url': memo.imageUrl,
      // 처음 보는 메모라 로컬 사본이 아직 없다. 사진은 동기화 이후
      // hydration([BookNoteRepository.hydrateLocalImages])이 내려받는다.
      'local_image_path': null,
      'is_important': memo.isImportant ? 1 : 0,
      'sort_order': memo.sortOrder,
      'deleted_at': null,
      'created_at': memo.createdAt.toUtc().toIso8601String(),
      'updated_at': memo.updatedAt.toUtc().toIso8601String(),
      'is_dirty': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int?> _findLocalNoteIdByServerId(
    Transaction txn,
    int serverNoteId,
  ) async {
    final rows = await txn.query(
      'book_note',
      columns: ['id'],
      where: 'server_id = ?',
      whereArgs: [serverNoteId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['id'] as int;
  }

  Future<int?> _findLocalUserBookIdByServerId(
    Transaction txn,
    int serverUserBookId,
  ) async {
    final rows = await txn.query(
      'user_book',
      columns: ['user_book_id'],
      where: '(server_id = ? OR user_book_id = ?) AND pending_delete = 0',
      whereArgs: [serverUserBookId, serverUserBookId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['user_book_id'] as int;
  }

  Future<List<int>> _localUserBookIdsForServerIds(
    Transaction txn,
    List<int> serverUserBookIds,
  ) async {
    if (serverUserBookIds.isEmpty) return const [];
    final placeholders = List.filled(serverUserBookIds.length, '?').join(', ');
    final rows = await txn.query(
      'user_book',
      columns: ['user_book_id'],
      where: 'server_id IN ($placeholders) OR user_book_id IN ($placeholders)',
      whereArgs: [...serverUserBookIds, ...serverUserBookIds],
    );
    return rows
        .map((row) => row['user_book_id'] as int)
        .toList(growable: false);
  }

  /// [activeUserBookIds]가 비어 있으면(이론상 발생하지 않아야 하지만,
  /// 방어적으로) 아무것도 지우지 않는다 — 빈 목록을 "책이 하나도 없다"로
  /// 오인해 전체 삭제로 번지는 사고를 막는다.
  Future<void> _deleteMissingNotesTxn(
    Transaction txn,
    int ownerUserId,
    List<int> activeUserBookIds,
    List<int> serverNoteIds,
  ) async {
    if (activeUserBookIds.isEmpty) return;
    final bookPlaceholders = List.filled(
      activeUserBookIds.length,
      '?',
    ).join(', ');
    if (serverNoteIds.isEmpty) {
      await txn.delete(
        'book_note',
        where:
            'owner_user_id = ? AND server_id IS NOT NULL AND is_dirty = 0 '
            'AND user_book_id IN ($bookPlaceholders) '
            'AND NOT EXISTS (SELECT 1 FROM book_note_memo '
            'WHERE note_id = book_note.id AND is_dirty = 1)',
        whereArgs: [ownerUserId, ...activeUserBookIds],
      );
      return;
    }
    final notePlaceholders = List.filled(serverNoteIds.length, '?').join(', ');
    await txn.delete(
      'book_note',
      where:
          'owner_user_id = ? AND server_id IS NOT NULL '
          'AND server_id NOT IN ($notePlaceholders) AND is_dirty = 0 '
          'AND user_book_id IN ($bookPlaceholders) '
          'AND NOT EXISTS (SELECT 1 FROM book_note_memo '
          'WHERE note_id = book_note.id AND is_dirty = 1)',
      whereArgs: [ownerUserId, ...serverNoteIds, ...activeUserBookIds],
    );
  }

  Future<void> _deleteMissingMemosTxn(
    Transaction txn,
    int ownerUserId,
    List<int> activeUserBookIds,
    List<int> serverMemoIds,
  ) async {
    if (activeUserBookIds.isEmpty) return;
    final bookPlaceholders = List.filled(
      activeUserBookIds.length,
      '?',
    ).join(', ');
    if (serverMemoIds.isEmpty) {
      await txn.delete(
        'book_note_memo',
        where:
            'server_id IS NOT NULL AND is_dirty = 0 AND note_id IN '
            '(SELECT id FROM book_note WHERE owner_user_id = ? '
            'AND user_book_id IN ($bookPlaceholders))',
        whereArgs: [ownerUserId, ...activeUserBookIds],
      );
      return;
    }
    final memoPlaceholders = List.filled(serverMemoIds.length, '?').join(', ');
    await txn.delete(
      'book_note_memo',
      where:
          'server_id IS NOT NULL AND server_id NOT IN ($memoPlaceholders) '
          'AND is_dirty = 0 AND note_id IN '
          '(SELECT id FROM book_note WHERE owner_user_id = ? '
          'AND user_book_id IN ($bookPlaceholders))',
      whereArgs: [...serverMemoIds, ownerUserId, ...activeUserBookIds],
    );
  }

  // ---------------------------------------------------------------------
  // 로컬 → 서버 저장 모드 재전환 Import 전용
  // ---------------------------------------------------------------------

  /// Import 대상 조회: 활성 노트 전체.
  Future<List<BookNote>> getAllActiveNotes({required int ownerUserId}) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_note',
      where: 'owner_user_id = ? AND deleted_at IS NULL',
      whereArgs: [ownerUserId],
    );
    return rows.map(_noteFromRow).toList(growable: false);
  }

  /// Import 대상 조회: 활성 노트에 속한 활성 메모 전체.
  Future<List<BookNoteMemo>> getAllActiveMemos({
    required int ownerUserId,
  }) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.rawQuery(
      '''
      SELECT m.* FROM book_note_memo m
      INNER JOIN book_note n ON n.id = m.note_id
      WHERE m.deleted_at IS NULL AND n.deleted_at IS NULL AND n.owner_user_id = ?
      ''',
      [ownerUserId],
    );
    return rows.map(_memoFromRow).toList(growable: false);
  }

  /// Import 전 멱등 키를 한 번 발급해 고정한다([BookNoteMemo.clientRequestId]가
  /// 없는 행 — 서버 동기화로만 내려온 옛 데이터 등). 이미 있는 값은 건드리지 않는다.
  Future<void> ensureMemoClientRequestIds() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(
      'book_note_memo',
      columns: ['id'],
      where: 'client_request_id IS NULL',
    );
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      for (final row in rows) {
        await txn.update(
          'book_note_memo',
          {'client_request_id': const Uuid().v4()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
  }

  /// Import `/complete` 성공 후에만 노트/메모의 서버 ID를 확정한다(청크
  /// 응답 즉시 반영하지 않는 이유는 [BookshelfDao.applyImportResults] 참고).
  /// [memoImageUrlByLocalId]는 이번 세션에서 새로 업로드한 사진의 R2 키만
  /// 담는다(있는 메모만).
  ///
  /// [executor]는 다른 도메인과 하나의 트랜잭션을 공유하기 위한 것이다
  /// ([BookshelfDao.applyImportResults] 문서 참고).
  Future<void> applyImportResults(
    DatabaseExecutor executor, {
    required Map<int, int> noteServerIdByLocalId,
    required Map<int, int> memoServerIdByLocalId,
    required Map<int, String> memoImageUrlByLocalId,
  }) async {
    for (final entry in noteServerIdByLocalId.entries) {
      await executor.update(
        'book_note',
        {'server_id': entry.value, 'is_dirty': 0},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
    for (final entry in memoServerIdByLocalId.entries) {
      final imageUrl = memoImageUrlByLocalId[entry.key];
      await executor.update(
        'book_note_memo',
        {'server_id': entry.value, 'is_dirty': 0, 'image_url': ?imageUrl},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
  }

  Future<int> _nextLocalId(Transaction txn, String table) async {
    final rows = await txn.rawQuery('SELECT MIN(id) AS min_id FROM $table');
    final current = rows.single['min_id'] as int?;
    return current != null && current <= 0 ? current - 1 : -1;
  }

  Future<void> _requireActiveNote(
    Transaction txn, {
    required int ownerUserId,
    required int userBookId,
    required int noteId,
  }) async {
    final rows = await txn.query(
      'book_note',
      columns: ['id'],
      where:
          'id = ? AND owner_user_id = ? AND user_book_id = ? '
          'AND deleted_at IS NULL',
      whereArgs: [noteId, ownerUserId, userBookId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Note not found');
  }

  static BookNote _noteFromRow(Map<String, Object?> row) {
    return BookNote(
      id: row['id'] as int,
      serverId: row['server_id'] as int?,
      userBookId: row['user_book_id'] as int,
      title: row['title'] as String?,
      deletedAt: _parseNullable(row['deleted_at'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      isDirty: (row['is_dirty'] as int) == 1,
    );
  }

  static BookNoteMemo _memoFromRow(Map<String, Object?> row) {
    final createdAt = DateTime.parse(row['created_at'] as String);
    final updatedAt = row['updated_at'] as String?;
    return BookNoteMemo(
      id: row['id'] as int,
      serverId: row['server_id'] as int?,
      clientRequestId: row['client_request_id'] as String?,
      noteId: row['note_id'] as int,
      type: BookNoteMemoType.fromDb(row['memo_type'] as String),
      startPage: row['start_page'] as int?,
      endPage: row['end_page'] as int?,
      content: row['content'] as String?,
      imageUrl: row['image_url'] as String?,
      localImagePath: row['local_image_path'] as String?,
      isImportant: (row['is_important'] as int) == 1,
      sortOrder: row['sort_order'] as int,
      deletedAt: _parseNullable(row['deleted_at'] as String?),
      createdAt: createdAt,
      updatedAt: updatedAt == null ? createdAt : DateTime.parse(updatedAt),
      isDirty: (row['is_dirty'] as int) == 1,
    );
  }

  static DateTime? _parseNullable(String? value) =>
      value == null ? null : DateTime.parse(value);
}
