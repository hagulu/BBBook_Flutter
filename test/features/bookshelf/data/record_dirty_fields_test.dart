import 'dart:io';

import 'package:bbbook/core/network/patch_field.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_dao.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/bookshelf/models/book_item.dart';
import 'package:bbbook/features/bookshelf/models/book_status.dart';
import 'package:bbbook/features/bookshelf/models/record_patch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 로컬 우선 편집이 "무엇을 바꿨는지"(`user_book.dirty_fields`)를 남겨,
/// 나중에 재시도하는 push가 바꾼 필드만 보내고 지운 필드는 명시적 null로
/// 보내는지 확인한다(api-doc/api-me-books-userBookId-patch.md).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dao = BookshelfDao();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final databaseDirectory = await Directory.systemTemp.createTemp(
      'bookshelf_dirty_fields_test',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    await databaseFactory.deleteDatabase(
      path.join(databaseDirectory.path, 'bookshelf.db'),
    );
    await BookshelfDatabase.instance();
  });

  setUp(() async {
    await BookshelfDatabase.clearAll();
  });

  BookItem serverItem() {
    final now = DateTime.utc(2026, 8, 20);
    return BookItem(
      userBookId: 1,
      serverId: 1,
      title: '책',
      status: BookStatus.reading,
      currentPage: 10,
      myRating: 4,
      shortReview: '좋았다',
      isMasterpiece: false,
      sourceType: 'EBOOK',
      rereadCount: 0,
      difficulty: 'EASY',
      platformName: '리디북스',
      tags: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<Map<String, dynamic>> pushBodyFor(int userBookId) async {
    final dirty = await dao.getDirtyRecord(userBookId);
    return RecordPatch.fromSnapshot(
      dirty!.item,
      changedFields: dirty.changedFields,
    ).toJson();
  }

  test('연속 편집은 바꾼 필드 목록에 누적되고, 지운 값은 명시적 null로 나간다', () async {
    final base = serverItem();
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);

    // 1) 진행 쪽수 수정
    final first = base.copyWithRecord(
      const RecordPatch(currentPage: 55),
      updatedAt: DateTime.utc(2026, 8, 26, 1),
    );
    await dao.applyLocalEdit(first, changedFields: {'currentPage'});

    // 2) 이어서 평점 지우기(아직 push 전)
    final second = first.copyWithRecord(
      const RecordPatch(myRating: PatchField.clear()),
      updatedAt: DateTime.utc(2026, 8, 26, 2),
    );
    await dao.applyLocalEdit(second, changedFields: {'myRating'});

    final dirty = await dao.getDirtyRecord(1);
    expect(dirty!.changedFields, {'currentPage', 'myRating'});
    expect(dirty.baseUpdatedAt, base.updatedAt);

    final body = await pushBodyFor(1);
    expect(body['currentPage'], 55);
    expect(body.containsKey('myRating'), isTrue);
    expect(body['myRating'], isNull);
    // 건드리지 않은 필드는 서버 값이 유지되도록 요청에서 빠진다.
    expect(body.containsKey('shortReview'), isFalse);
    expect(body.containsKey('platformName'), isFalse);
    expect(body.containsKey('difficulty'), isFalse);
  });

  test('push 확정 후에는 바꾼 필드 목록도 함께 비워진다', () async {
    final base = serverItem();
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);
    final edited = base.copyWithRecord(
      const RecordPatch(difficulty: PatchField.clear()),
      updatedAt: DateTime.utc(2026, 8, 26),
    );
    await dao.applyLocalEdit(edited, changedFields: {'difficulty'});

    final applied = await dao.confirmPush(
      edited,
      capturedUpdatedAt: edited.updatedAt,
    );

    expect(applied, isTrue);
    expect(await dao.getDirtyRecord(1), isNull);

    // 다음 편집은 이전 목록을 이어받지 않는다.
    final next = edited.copyWithRecord(
      const RecordPatch(currentPage: 3),
      updatedAt: DateTime.utc(2026, 8, 27),
    );
    await dao.applyLocalEdit(next, changedFields: {'currentPage'});
    expect((await dao.getDirtyRecord(1))!.changedFields, {'currentPage'});
  });

  test('push가 오가는 사이 새 편집이 들어오면 서버 응답이 그 편집을 덮지 않는다', () async {
    final base = serverItem();
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);
    final pushed = base.copyWithRecord(
      const RecordPatch(currentPage: 40),
      updatedAt: DateTime.utc(2026, 8, 26, 1),
    );
    await dao.applyLocalEdit(pushed, changedFields: {'currentPage'});

    // 요청이 오가는 동안 사용자가 한 번 더 편집했다.
    final newer = pushed.copyWithRecord(
      const RecordPatch(shortReview: PatchField.clear()),
      updatedAt: DateTime.utc(2026, 8, 26, 2),
    );
    await dao.applyLocalEdit(newer, changedFields: {'shortReview'});

    // 뒤늦게 도착한 push 응답(보낸 시점 스냅샷 기준).
    final serverResponse = pushed.copyWithRecord(
      const RecordPatch(),
      updatedAt: DateTime.utc(2026, 8, 26, 1, 30),
    );
    final applied = await dao.confirmPush(
      serverResponse,
      capturedUpdatedAt: pushed.updatedAt,
    );

    expect(applied, isFalse);
    final dirty = await dao.getDirtyRecord(1);
    // 새 편집과 그 필드 목록이 살아 있어야 다음 push가 다시 보낸다.
    expect(dirty!.item.shortReview, isNull);
    expect(dirty.changedFields, {'currentPage', 'shortReview'});
    // 충돌 검사 기준값만 서버가 확인해 준 최신 값으로 당겨진다.
    expect(dirty.baseUpdatedAt, DateTime.utc(2026, 8, 26, 1, 30));
  });

  test('409 거부 중에 새 편집이 들어왔으면 그 편집을 되돌리지 않는다', () async {
    final base = serverItem();
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);
    final pushed = base.copyWithRecord(
      const RecordPatch(currentPage: 40),
      updatedAt: DateTime.utc(2026, 8, 26, 1),
    );
    await dao.applyLocalEdit(pushed, changedFields: {'currentPage'});
    final newer = pushed.copyWithRecord(
      const RecordPatch(difficulty: PatchField.value('HARD')),
      updatedAt: DateTime.utc(2026, 8, 26, 2),
    );
    await dao.applyLocalEdit(newer, changedFields: {'difficulty'});

    final reverted = await dao.resolveConflict(
      1,
      capturedUpdatedAt: pushed.updatedAt,
    );

    expect(reverted, isFalse);
    final dirty = await dao.getDirtyRecord(1);
    expect(dirty!.item.difficulty, 'HARD');
    expect(dirty.changedFields, {'currentPage', 'difficulty'});
    // 기준값은 비워 다음 push가 충돌 검사 없이 최신 편집을 보낸다.
    expect(dirty.baseUpdatedAt, isNull);
  });

  test('409 거부 시 새 편집이 없었으면 dirty를 풀어 동기화가 되돌리게 한다', () async {
    final base = serverItem();
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);
    final pushed = base.copyWithRecord(
      const RecordPatch(currentPage: 40),
      updatedAt: DateTime.utc(2026, 8, 26, 1),
    );
    await dao.applyLocalEdit(pushed, changedFields: {'currentPage'});

    final reverted = await dao.resolveConflict(
      1,
      capturedUpdatedAt: pushed.updatedAt,
    );

    expect(reverted, isTrue);
    expect(await dao.getDirtyRecord(1), isNull);
  });

  test('목록 없이 쌓여 있던 레거시 편집은 새 편집에 흡수돼 함께 전송된다', () async {
    final base = serverItem();
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);
    // DB v15 이하에서 쌓인 dirty 행 재현: dirty지만 목록이 없다.
    final db = await BookshelfDatabase.instance();
    await db.update(
      'user_book',
      {'is_dirty': 1, 'dirty_fields': null},
      where: 'user_book_id = ?',
      whereArgs: [1],
    );

    final edited = base.copyWithRecord(
      const RecordPatch(platformName: PatchField.clear()),
      updatedAt: DateTime.utc(2026, 8, 26),
    );
    await dao.applyLocalEdit(edited, changedFields: {'platformName'});

    final body = await pushBodyFor(1);
    // 새 편집(지움)은 명시적 null로 나가고,
    expect(body.containsKey('platformName'), isTrue);
    expect(body['platformName'], isNull);
    // 레거시 행이 그동안 보내던 값들도 빠지지 않는다.
    expect(body['shortReview'], '좋았다');
    expect(body['difficulty'], 'EASY');
    expect(body['currentPage'], 10);
  });

  test('책 정보 변경 표식은 기록 PATCH 필드로 전송되지 않는다', () async {
    final base = serverItem();
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);
    await dao.applyLocalEdit(
      base,
      changedFields: {bookInfoDirtyField, bookCoverDirtyField},
    );
    expect(await pushBodyFor(1), isEmpty);
    expect((await dao.getDirtyRecord(1))!.changedFields, {
      bookInfoDirtyField,
      bookCoverDirtyField,
    });
  });

  test('영구 실패는 전송만 지연하고 로컬 편집과 수동 재시도로 다시 활성화한다', () async {
    final base = serverItem();
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);
    await dao.applyLocalEdit(base, changedFields: {'myRating'});
    final now = DateTime.utc(2026, 9, 8);
    await dao.deferPush(
      1,
      capturedUpdatedAt: base.updatedAt,
      reason: 'record_rejected_400',
      now: now,
    );
    expect(await dao.canRetryPush(1, now: now), isFalse);
    expect(await dao.hasRetryableChanges(now: now), isFalse);
    expect(await dao.hasSyncFailures(), isTrue);
    expect(await dao.getDirtyRecord(1), isNotNull);
    expect(
      await dao.canRetryPush(1, now: now.add(const Duration(minutes: 10))),
      isTrue,
    );

    await dao.resetRetryDelays();
    expect(await dao.canRetryPush(1, now: now), isTrue);
    await dao.deferPush(
      1,
      capturedUpdatedAt: base.updatedAt,
      reason: 'record_rejected_400',
      now: now,
    );
    // 동일 입력의 두 번째 실패는 20분 뒤 재시도한다.
    expect(
      await dao.canRetryPush(1, now: now.add(const Duration(minutes: 10))),
      isFalse,
    );
    await dao.applyLocalEdit(base, changedFields: {'myRating'});
    expect(await dao.canRetryPush(1, now: now), isTrue);
    expect(await dao.hasSyncFailures(), isFalse);
  });

  test('지연 도착한 이전 편집의 실패는 새 편집의 전송을 막지 않는다', () async {
    final base = serverItem();
    await dao.upsertOne(base);
    final edited = base.copyWithRecord(
      const RecordPatch(currentPage: 20),
      updatedAt: base.updatedAt.add(const Duration(seconds: 1)),
    );
    await dao.applyLocalEdit(edited, changedFields: {'currentPage'});
    await dao.deferPush(
      1,
      capturedUpdatedAt: base.updatedAt,
      reason: 'record_rejected_400',
    );
    expect(await dao.canRetryPush(1), isTrue);
    expect(await dao.hasSyncFailures(), isFalse);
  });

  test('표지 유실 시 다른 필드는 확정하고 표지 교체만 미전송으로 보존한다', () async {
    final base = serverItem();
    await dao.upsertOne(base);
    final local = base.copyWithBookInfo(
      title: '수정한 제목',
      author: base.author,
      publisher: base.publisher,
      statsTotalPages: base.statsTotalPages,
      displayTotalPages: base.displayTotalPages,
      displayCategoryId: base.displayCategoryId,
      category: base.category,
      coverImageUrl: 'book_covers/missing.jpg',
      isbn13: base.isbn13,
      bookId: base.bookId,
      updatedAt: DateTime.utc(2026, 9, 8),
    );
    await dao.applyLocalEdit(
      local,
      changedFields: {bookInfoDirtyField, bookCoverDirtyField, 'myRating'},
    );
    await dao.confirmPush(
      local,
      capturedUpdatedAt: local.updatedAt,
      retainPendingCover: true,
    );
    final dirty = (await dao.getDirtyRecord(1))!;
    expect(dirty.item.title, '수정한 제목');
    expect(dirty.item.coverImageUrl, 'book_covers/missing.jpg');
    expect(dirty.changedFields, {bookInfoDirtyField, bookCoverDirtyField});
    expect(await pushBodyFor(1), isEmpty);
  });

  test('로컬 삭제는 늦은 PATCH·409·pull 응답으로 되살아나지 않는다', () async {
    final base = serverItem();
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);
    await dao.deleteOne(1, queueServerDelete: true);
    final deleted = (await dao.getDirtyRecord(1))!;
    expect(await dao.getById(1), isNull);
    expect(await dao.getByStatuses(BookStatus.values), isEmpty);
    expect(
      await dao.confirmPush(base, capturedUpdatedAt: deleted.item.updatedAt),
      isFalse,
    );
    expect(
      await dao.resolveConflict(1, capturedUpdatedAt: deleted.item.updatedAt),
      isFalse,
    );
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);
    expect(await dao.getById(1), isNull);
    expect(await dao.getDirtyRecord(1), isNotNull);

    await dao.confirmDelete(1);
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);
    expect(await dao.getById(1), isNull);
    expect(await dao.getDirtyRecord(1), isNull);
  });

  test('업로드한 표지는 로컬 사본을 유지하며 후속 pull에서도 사용한다', () async {
    final base = serverItem();
    await dao.upsertOne(base, syncedUpdatedAt: base.updatedAt);
    final local = base.copyWithBookInfo(
      title: base.title,
      author: base.author,
      publisher: base.publisher,
      statsTotalPages: base.statsTotalPages,
      displayTotalPages: base.displayTotalPages,
      displayCategoryId: base.displayCategoryId,
      category: base.category,
      coverImageUrl: 'book_covers/local.jpg',
      isbn13: base.isbn13,
      bookId: base.bookId,
      updatedAt: DateTime.utc(2026, 9, 1),
    );
    await dao.applyLocalEdit(
      local,
      changedFields: {bookInfoDirtyField, bookCoverDirtyField},
    );
    final response = local.copyWithBookInfo(
      title: local.title,
      author: local.author,
      publisher: local.publisher,
      statsTotalPages: local.statsTotalPages,
      displayTotalPages: local.displayTotalPages,
      displayCategoryId: local.displayCategoryId,
      category: local.category,
      coverImageUrl: 'https://example.test/cover.jpg',
      isbn13: local.isbn13,
      bookId: local.bookId,
      updatedAt: DateTime.utc(2026, 9, 1, 1),
    );
    await dao.confirmPush(
      response,
      capturedUpdatedAt: local.updatedAt,
      localCoverPath: local.coverImageUrl,
    );
    expect((await dao.getById(1))?.coverImageUrl, local.coverImageUrl);
    await dao.upsertOne(response, syncedUpdatedAt: response.updatedAt);
    expect((await dao.getById(1))?.coverImageUrl, local.coverImageUrl);
    expect(
      (await dao.findLocalImagePathsForBook(1)).coverImage,
      local.coverImageUrl,
    );
  });
}
