import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../bookshelf/data/bookshelf_database.dart';
import '../../book_reflection/services/book_reflection_content_adapter.dart';
import '../../bookshelf/data/bookshelf_dao.dart';
import '../../tag/data/tag_dao.dart';
import '../models/record_archive.dart';

/// DB와 포맷의 대응은 이 경계에만 둔다. PK/서버 상태를 직렬화하지 않는다.
const _bookColumns = {
  'title': 'title',
  'author': 'author',
  'publisher': 'publisher',
  'isbn13': 'isbn13',
  'category': 'category',
  'statsTotalPages': 'stats_total_pages',
  'displayTotalPages': 'display_total_pages',
  'status': 'status',
  'currentPage': 'current_page',
  'myRating': 'my_rating',
  'shortReview': 'short_review',
  'isMasterpiece': 'is_masterpiece',
  'wantToReread': 'want_to_reread',
  'rereadCount': 'reread_count',
  'difficulty': 'difficulty',
  'sourceType': 'source_type',
  'platformName': 'platform_name',
  'discoverySource': 'discovery_source',
  'startedAt': 'started_at',
  'finishedAt': 'finished_at',
  'libraryDueAt': 'library_due_at',
  'createdAt': 'created_at',
  'updatedAt': 'updated_at',
};
const _noteColumns = {
  'title': 'title',
  'createdAt': 'created_at',
  'updatedAt': 'updated_at',
};
const _memoColumns = {
  'type': 'memo_type',
  'startPage': 'start_page',
  'endPage': 'end_page',
  'content': 'content',
  'isImportant': 'is_important',
  'sortOrder': 'sort_order',
  'createdAt': 'created_at',
  'updatedAt': 'updated_at',
};
const _reflectionColumns = {
  'type': 'reflection_type',
  'title': 'title',
  'contentText': 'content_text',
  'isPublic': 'is_public',
  'isHidden': 'is_hidden',
  'createdAt': 'created_at',
  'updatedAt': 'updated_at',
};
const _booleans = {
  'isMasterpiece',
  'wantToReread',
  'isImportant',
  'isPublic',
  'isHidden',
};
const _recordDirtyFields = [
  'status',
  'currentPage',
  'myRating',
  'shortReview',
  'isMasterpiece',
  'sourceType',
  'rereadCount',
  'wantToReread',
  'difficulty',
  'startedAt',
  'finishedAt',
  'libraryDueAt',
  'platformName',
  'discoverySource',
  bookInfoDirtyField,
];

class ArchiveImageSource {
  const ArchiveImageSource(this.kind, this.local, this.remote);
  final String kind;
  final String? local;
  final String? remote;
}

class ArchiveSnapshot {
  ArchiveSnapshot(this.records, this.images);
  final RecordArchive records;

  /// 이미지 확보 전의 내부 참조. ZIP/JSON에는 기록하지 않는다.
  final Map<String, ArchiveImageSource> images;
}

class RecordArchiveDao {
  RecordArchiveDao({Future<Database> Function()? database})
    : _database = database ?? BookshelfDatabase.instance;
  final Future<Database> Function() _database;

  Future<ArchiveSnapshot> snapshot(int ownerUserId) async {
    final db = await _database();
    return db.transaction((txn) async {
      final books = await txn.query(
        'user_book',
        where: 'pending_delete = 0',
        orderBy: 'user_book_id',
      );
      final notes = await txn.rawQuery(
        'SELECT n.* FROM book_note n JOIN user_book b ON b.user_book_id=n.user_book_id WHERE n.owner_user_id=? AND n.deleted_at IS NULL AND b.pending_delete=0 ORDER BY n.id',
        [ownerUserId],
      );
      final memos = await txn.rawQuery(
        'SELECT m.* FROM book_note_memo m JOIN book_note n ON n.id=m.note_id JOIN user_book b ON b.user_book_id=n.user_book_id WHERE n.owner_user_id=? AND n.deleted_at IS NULL AND m.deleted_at IS NULL AND b.pending_delete=0 ORDER BY m.sort_order,m.id',
        [ownerUserId],
      );
      final reflections = await txn.rawQuery(
        'SELECT r.* FROM book_reflection r JOIN user_book b ON b.user_book_id=r.user_book_id WHERE r.owner_user_id=? AND r.deleted_at IS NULL AND b.pending_delete=0 ORDER BY r.id',
        [ownerUserId],
      );
      final tags = await txn.query(
        'tag',
        where: 'deleted_at IS NULL',
        orderBy: 'id',
      );
      final maps = await txn.rawQuery(
        'SELECT m.user_book_id,t.name FROM user_book_tag_map m JOIN tag t ON t.id=m.tag_id WHERE m.deleted_at IS NULL AND t.deleted_at IS NULL ORDER BY m.id',
      );
      final categories = await txn.query('book_category');
      final links = await txn.query('reflection_image_local');
      final images = <String, ArchiveImageSource>{};
      final bookIds = <Object?, String>{};
      final noteIds = <Object?, String>{};
      Future<String> identity(
        String table,
        Map<String, Object?> row,
        String pk,
      ) async {
        final existing = row['client_request_id'] as String?;
        if (existing != null && existing.isNotEmpty) return existing;
        final id = const Uuid().v4();
        await txn.update(
          table,
          {'client_request_id': id},
          where: '$pk = ?',
          whereArgs: [row[pk]],
        );
        return id;
      }

      Map<String, dynamic> values(
        Map<String, Object?> row,
        Map<String, String> columns,
      ) => {
        for (final e in columns.entries)
          e.key: _booleans.contains(e.key) ? row[e.value] == 1 : row[e.value],
      };
      final bookDtos = <ArchiveRecord>[];
      for (final row in books) {
        final id = await identity('user_book', row, 'user_book_id');
        bookIds[row['user_book_id']] = id;
        final rawCover = row['cover_image_url'] as String?;
        final local = row['local_cover_url'] == rawCover
            ? row['local_cover_path'] as String?
            : null;
        final key = 'cover_$id';
        if (rawCover != null) {
          images[key] = ArchiveImageSource(
            'cover',
            local ?? rawCover,
            rawCover,
          );
        }
        bookDtos.add(
          ArchiveRecord(
            id: id,
            values: {
              ...values(row, _bookColumns),
              'categoryCode': categories
                  .where((c) => c['id'] == row['display_category_id'])
                  .firstOrNull?['code'],
              'coverImage': rawCover == null ? null : key,
              'tags': maps
                  .where((m) => m['user_book_id'] == row['user_book_id'])
                  .map((m) => m['name'] as String)
                  .toSet()
                  .toList(),
            },
          ),
        );
      }
      final noteDtos = <ArchiveRecord>[];
      for (final row in notes) {
        final id = const Uuid().v4();
        noteIds[row['id']] = id;
        noteDtos.add(
          ArchiveRecord(
            id: id,
            values: {
              ...values(row, _noteColumns),
              'bookId': bookIds[row['user_book_id']],
            },
          ),
        );
      }
      final memoDtos = <ArchiveRecord>[];
      for (final row in memos) {
        final id = await identity('book_note_memo', row, 'id');
        final local = row['local_image_path'] as String?;
        final remote = row['image_url'] as String?;
        final key = 'memo_$id';
        if (local != null || remote != null) {
          images[key] = ArchiveImageSource('memo', local, remote);
        }
        memoDtos.add(
          ArchiveRecord(
            id: id,
            values: {
              ...values(row, _memoColumns),
              'updatedAt': row['updated_at'] ?? row['created_at'],
              'noteId': noteIds[row['note_id']],
              'image': images.containsKey(key) ? key : null,
            },
          ),
        );
      }
      final reflectionDtos = <ArchiveRecord>[];
      for (final row in reflections) {
        final id = await identity('book_reflection', row, 'id');
        final content = row['content_json'] == null
            ? null
            : jsonDecode(row['content_json'] as String);
        reflectionDtos.add(
          ArchiveRecord(
            id: id,
            values: {
              ...values(row, _reflectionColumns),
              'bookId': bookIds[row['user_book_id']],
              'content': content,
            },
          ),
        );
        for (final link in links.where(
          (l) => l['reflection_id'] == row['id'],
        )) {
          images['reflection_${id}_${link['remote_image_url']}'] =
              ArchiveImageSource(
                'reflection',
                link['local_image_path'] as String?,
                link['remote_image_url'] as String?,
              );
        }
      }
      return ArchiveSnapshot(
        RecordArchive(
          exportedAt: DateTime.now().toUtc().toIso8601String(),
          books: bookDtos,
          notes: noteDtos,
          memos: memoDtos,
          reflections: reflectionDtos,
          tags: tags.map((t) => t['name'] as String).toSet().toList(),
        ),
        images,
      );
    });
  }

  /// 파일 준비 완료 후 호출. 전체 DB 반영은 한 트랜잭션이며 기존 dirty push가 후속 전송한다.
  Future<Set<String>> restore(
    RecordArchive archive,
    int ownerUserId,
    Map<String, String> images, {
    required bool Function() sessionValid,
  }) async {
    final db = await _database();
    return db.transaction((txn) async {
      final usedImages = <String>{};
      if (!sessionValid()) {
        throw const ArchiveException('계정 상태가 변경되어 가져오기를 중단했습니다.');
      }
      final bookIds = <String, int>{};
      final noteIds = <String, int>{};
      final now = DateTime.now().toUtc().toIso8601String();
      Map<String, Object?> rowValues(
        ArchiveRecord record,
        Map<String, String> columns,
      ) => {
        for (final e in columns.entries)
          e.value: _booleans.contains(e.key)
              ? (record[e.key] == true ? 1 : 0)
              : record[e.key],
      };
      for (final book in archive.books) {
        final sameIdentity = await txn.query(
          'user_book',
          where: 'client_request_id = ? AND pending_delete=0',
          whereArgs: [book.id],
          limit: 1,
        );
        final sameIsbn = book['isbn13'] == null
            ? <Map<String, Object?>>[]
            : await txn.query(
                'user_book',
                where: 'isbn13 = ? AND pending_delete=0',
                whereArgs: [book['isbn13']],
                limit: 1,
              );
        final existing = sameIdentity.isNotEmpty ? sameIdentity : sameIsbn;
        final id = existing.isEmpty
            ? await _nextId(txn, 'user_book', 'user_book_id')
            : existing.single['user_book_id'] as int;
        bookIds[book.id] = id;
        if (sameIdentity.isNotEmpty) continue;
        final category = book['categoryCode'] == null
            ? <Map<String, Object?>>[]
            : await txn.query(
                'book_category',
                where: 'code = ?',
                whereArgs: [book['categoryCode']],
                limit: 1,
              );
        final values = <String, Object?>{
          ...rowValues(book, _bookColumns),
          'display_category_id': category.firstOrNull?['id'],
          'is_dirty': 1,
          'updated_at': now,
          'dirty_fields': {
            ..._recordDirtyFields,
            if (existing.isEmpty && images[book['coverImage']] != null)
              bookCoverDirtyField,
            if (existing.isNotEmpty && existing.single['dirty_fields'] != null)
              ...(existing.single['dirty_fields'] as String).split(','),
          }.join(','),
        };
        if (existing.isEmpty) {
          final cover = images[book['coverImage']];
          if (cover != null) usedImages.add(cover);
          await txn.insert('user_book', {
            ...values,
            'user_book_id': id,
            'client_request_id': book.id,
            'cover_image_url': cover,
          });
        } else {
          // 기존 Import와 같이 ISBN 대응 책의 표지는 보존한다.
          await txn.update(
            'user_book',
            values,
            where: 'user_book_id = ?',
            whereArgs: [id],
          );
        }
      }
      for (final tag in archive.tags) {
        await const TagDao().ensureArchiveTag(txn, tag);
      }
      for (final book in archive.books) {
        for (final tag in (book['tags'] as List).cast<String>()) {
          await const TagDao().addTagLocal(
            userBookId: bookIds[book.id]!,
            name: tag,
            transaction: txn,
          );
        }
      }
      for (final note in archive.notes) {
        final bookId = bookIds[note['bookId']]!;
        final childMemos = archive.memos
            .where((m) => m['noteId'] == note.id)
            .toList();
        final matched = <int>{};
        for (final memo in childMemos) {
          final rows = await txn.rawQuery(
            'SELECT n.id FROM book_note_memo m JOIN book_note n ON n.id=m.note_id WHERE m.client_request_id=? AND m.deleted_at IS NULL AND n.deleted_at IS NULL AND n.user_book_id=? AND n.owner_user_id=?',
            [memo.id, bookId, ownerUserId],
          );
          matched.addAll(rows.map((r) => r['id'] as int));
        }
        if (matched.length > 1) {
          throw const ArchiveException('기존 노트와 기록의 연결이 달라 가져올 수 없습니다.');
        }
        if (childMemos.isEmpty) {
          final rows = await txn.rawQuery(
            'SELECT n.id FROM book_note n WHERE n.user_book_id=? AND n.owner_user_id=? AND n.title IS ? AND n.deleted_at IS NULL AND NOT EXISTS (SELECT 1 FROM book_note_memo m WHERE m.note_id=n.id AND m.deleted_at IS NULL) ORDER BY n.id',
            [bookId, ownerUserId, note['title']],
          );
          matched.addAll(
            rows
                .map((r) => r['id'] as int)
                .where((id) => !noteIds.values.contains(id))
                .take(1),
          );
        }
        final id = matched.firstOrNull ?? await _nextId(txn, 'book_note', 'id');
        noteIds[note.id] = id;
        if (matched.isEmpty) {
          await txn.insert('book_note', {
            ...rowValues(note, _noteColumns),
            'id': id,
            'owner_user_id': ownerUserId,
            'user_book_id': bookId,
            'is_dirty': 1,
          });
        }
      }
      for (final memo in archive.memos) {
        final rows = await txn.query(
          'book_note_memo',
          where: 'client_request_id=? AND deleted_at IS NULL',
          whereArgs: [memo.id],
        );
        if (rows.isNotEmpty) {
          if (rows.any((r) => r['note_id'] != noteIds[memo['noteId']])) {
            throw const ArchiveException('기존 메모의 연결이 달라 가져올 수 없습니다.');
          }
          continue;
        }
        final memoImage = images[memo['image']];
        if (memoImage != null) usedImages.add(memoImage);
        await txn.insert('book_note_memo', {
          ...rowValues(memo, _memoColumns),
          'id': await _nextId(txn, 'book_note_memo', 'id'),
          'note_id': noteIds[memo['noteId']],
          'client_request_id': memo.id,
          'local_image_path': images[memo['image']],
          'is_dirty': 1,
        });
      }
      for (final reflection in archive.reflections) {
        final rows = await txn.query(
          'book_reflection',
          where: 'client_request_id=? AND deleted_at IS NULL',
          whereArgs: [reflection.id],
        );
        if (rows.isNotEmpty) {
          if (rows.any(
            (r) =>
                r['user_book_id'] != bookIds[reflection['bookId']] ||
                r['owner_user_id'] != ownerUserId,
          )) {
            throw const ArchiveException('기존 독후감의 연결이 달라 가져올 수 없습니다.');
          }
          continue;
        }
        usedImages.addAll(
          const BookReflectionContentAdapter().imageSources(
            reflection['content'] as Map<String, dynamic>?,
          ),
        );
        await txn.insert('book_reflection', {
          ...rowValues(reflection, _reflectionColumns),
          'id': await _nextId(txn, 'book_reflection', 'id'),
          'owner_user_id': ownerUserId,
          'user_book_id': bookIds[reflection['bookId']],
          'client_request_id': reflection.id,
          'content_json': reflection['content'] == null
              ? null
              : jsonEncode(reflection['content']),
          'is_dirty': 1,
        });
      }
      if (!sessionValid()) {
        throw const ArchiveException('계정 상태가 변경되어 가져오기를 중단했습니다.');
      }
      return usedImages;
    });
  }

  Future<int> _nextId(Transaction txn, String table, String pk) async {
    final min =
        Sqflite.firstIntValue(
          await txn.rawQuery('SELECT MIN($pk) FROM $table'),
        ) ??
        0;
    return min < 0 ? min - 1 : -1;
  }
}
