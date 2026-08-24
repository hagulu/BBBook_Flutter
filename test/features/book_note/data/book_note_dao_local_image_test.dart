import 'dart:io';

import 'package:bbbook/features/book_note/data/book_note_dao.dart';
import 'package:bbbook/features/book_note/models/book_note.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/record_sync/models/record_sync_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 메모 사진 로컬 사본(`local_image_path`) 관리 로직 테스트.
///
/// 서버 동기화는 이 컬럼을 모른다 — 같은 사진이면 보존하고, 서버에서 사진이
/// 교체됐을 때만 끊어야 한다. 이 규칙이 깨지면 매 동기화마다 사진을 다시
/// 내려받거나(보존 실패), 엉뚱한 옛 사진을 계속 보여주게 된다(교체 미감지).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dao = BookNoteDao();
  final now = DateTime.utc(2026, 8, 23);

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 테스트 파일은 병렬 실행되므로 파일마다 별도 DB 경로를 쓴다(같은
    // `bookshelf.db`를 공유하면 서로의 setUp이 남의 데이터를 지운다).
    final databaseDirectory = await Directory.systemTemp.createTemp(
      'bookshelf_test',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    final databasePath = path.join(databaseDirectory.path, 'bookshelf.db');
    await databaseFactory.deleteDatabase(databasePath);
    await BookshelfDatabase.instance();
  });

  setUp(() async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await txn.delete('book_note_memo');
      await txn.delete('book_note');
      await txn.delete('sync_meta');
    });
  });

  ServerBookNoteMemo serverPhoto({required String? imageUrl}) {
    return ServerBookNoteMemo(
      id: 500,
      noteId: 400,
      memoType: 'PHOTO',
      startPage: null,
      endPage: null,
      content: '사진 메모',
      imageUrl: imageUrl,
      isImportant: false,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> applyServerPhoto({required String? imageUrl}) {
    return dao.applyNoteChanges(
      ownerUserId: 7,
      upsertedNotes: [
        ServerBookNote(
          id: 400,
          userBookId: 20,
          title: '노트',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      deletedNoteIds: const [],
      upsertedNoteMemos: [serverPhoto(imageUrl: imageUrl)],
      deletedNoteMemoIds: const [],
      syncedAt: now,
    );
  }

  Future<BookNoteMemo> readMemo() async {
    final detail = await dao.findDetail(
      ownerUserId: 7,
      userBookId: 20,
      noteId: 400,
    );
    return detail!.memos.single;
  }

  test('내려받은 로컬 사본은 같은 사진이 다시 동기화돼도 유지된다', () async {
    const imageUrl = 'https://cdn.example.com/notes/400/photo-a.jpg';
    await applyServerPhoto(imageUrl: imageUrl);
    await dao.setLocalImagePath(
      localId: (await readMemo()).id,
      localImagePath: 'memo_images/remote_notes_400_photo-a.jpg',
      expectedImageUrl: imageUrl,
    );

    // 서명/만료 쿼리가 붙어 URL 문자열이 달라져도 같은 사진이다.
    await applyServerPhoto(imageUrl: '$imageUrl?sig=abc');

    final memo = await readMemo();
    expect(memo.localImagePath, 'memo_images/remote_notes_400_photo-a.jpg');
    expect(memo.imageUrl, '$imageUrl?sig=abc');
  });

  test('서버에서 사진이 교체되면 옛 로컬 사본 참조를 끊는다', () async {
    const imageUrl = 'https://cdn.example.com/notes/400/photo-a.jpg';
    await applyServerPhoto(imageUrl: imageUrl);
    await dao.setLocalImagePath(
      localId: (await readMemo()).id,
      localImagePath: 'memo_images/remote_notes_400_photo-a.jpg',
      expectedImageUrl: imageUrl,
    );

    await applyServerPhoto(
      imageUrl: 'https://cdn.example.com/notes/400/photo-b.jpg',
    );

    final memo = await readMemo();
    expect(memo.localImagePath, isNull);
    expect(memo.imageUrl, 'https://cdn.example.com/notes/400/photo-b.jpg');
    // 참조가 끊긴 파일은 orphan 정리 대상이 된다.
    expect(await dao.getAllLocalImagePaths(), isEmpty);
  });

  test('사진 내려받기 대상은 서버 사진만 있고 로컬 사본이 없는 메모다', () async {
    const imageUrl = 'https://cdn.example.com/notes/400/photo-a.jpg';
    await applyServerPhoto(imageUrl: imageUrl);

    final before = await dao.findPhotoMemosMissingLocalImage();
    expect(before.map((memo) => memo.imageUrl), [imageUrl]);

    await dao.setLocalImagePath(
      localId: before.single.id,
      localImagePath: 'memo_images/remote_notes_400_photo-a.jpg',
      expectedImageUrl: imageUrl,
    );
    expect(await dao.findPhotoMemosMissingLocalImage(), isEmpty);

    // 파일이 사라진 참조를 끊으면 다시 내려받기 대상이 된다.
    await dao.clearLocalImagePaths([
      'memo_images/remote_notes_400_photo-a.jpg',
    ]);
    expect(await dao.findPhotoMemosMissingLocalImage(), hasLength(1));
  });

  test('서버가 주지 않는 사진은 제외해 다음 사진이 자리를 얻는다', () async {
    const unavailable = 'https://cdn.example.com/notes/400/gone.jpg';
    const pending = 'https://cdn.example.com/notes/400/photo-b.jpg';
    await dao.applyNoteChanges(
      ownerUserId: 7,
      upsertedNotes: [
        ServerBookNote(
          id: 400,
          userBookId: 20,
          title: '노트',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      deletedNoteIds: const [],
      upsertedNoteMemos: [
        serverPhoto(imageUrl: unavailable),
        ServerBookNoteMemo(
          id: 501,
          noteId: 400,
          memoType: 'PHOTO',
          startPage: null,
          endPage: null,
          content: null,
          imageUrl: pending,
          isImportant: false,
          sortOrder: 1,
          createdAt: now,
          updatedAt: now.subtract(const Duration(days: 1)),
        ),
      ],
      deletedNoteMemoIds: const [],
      syncedAt: now,
    );

    // 서버가 주지 않는다고 확인된 사진을 제외하면 그 다음 사진이 대상이 된다.
    final all = await dao.findPhotoMemosMissingLocalImage();
    expect(all.first.imageUrl, unavailable);

    final next = await dao.findPhotoMemosMissingLocalImage(
      excludeImageUrls: const [unavailable],
    );
    expect(next.single.imageUrl, pending);

    // orphan 정리가 지켜야 할 "아직 연결되지 않은 사진"에는 둘 다 포함된다.
    expect(
      await dao.getPendingPhotoImageUrls(),
      containsAll(<String>[unavailable, pending]),
    );
  });

  test('로컬에서 만든 사진 메모는 업로드 전까지 image_url이 비어 있다', () async {
    final note = await dao.createNote(
      ownerUserId: 7,
      userBookId: 20,
      title: null,
    );
    final memo = await dao.createNoteMemo(
      ownerUserId: 7,
      userBookId: 20,
      noteId: note.id,
      draft: const BookNoteMemoDraft(
        type: BookNoteMemoType.photo,
        content: '오프라인 사진',
        imageChange: MemoImageChange.replaced,
      ),
      localImagePath: 'memo_images/memo_1.jpg',
    );

    expect(memo.localImagePath, 'memo_images/memo_1.jpg');
    expect(memo.imageUrl, isNull);
    expect(memo.isDirty, isTrue);

    // 사진을 그대로 둔 수정은 두 컬럼을 건드리지 않는다.
    final edited = await dao.updateNoteMemo(
      ownerUserId: 7,
      userBookId: 20,
      noteId: note.id,
      noteMemoId: memo.id,
      draft: const BookNoteMemoDraft(
        type: BookNoteMemoType.photo,
        content: '설명만 수정',
      ),
      localImagePath: null,
    );
    expect(edited.localImagePath, 'memo_images/memo_1.jpg');

    // 사진 제거는 두 컬럼을 함께 비운다.
    final cleared = await dao.updateNoteMemo(
      ownerUserId: 7,
      userBookId: 20,
      noteId: note.id,
      noteMemoId: memo.id,
      draft: const BookNoteMemoDraft(
        type: BookNoteMemoType.thought,
        content: '사진 제거',
        imageChange: MemoImageChange.cleared,
      ),
      localImagePath: null,
    );
    expect(cleared.localImagePath, isNull);
    expect(cleared.imageUrl, isNull);
  });

  test('서버 업로드 확정은 로컬 사본을 지우지 않고 서버 URL만 채운다', () async {
    final note = await dao.createNote(
      ownerUserId: 7,
      userBookId: 20,
      title: null,
    );
    final memo = await dao.createNoteMemo(
      ownerUserId: 7,
      userBookId: 20,
      noteId: note.id,
      draft: const BookNoteMemoDraft(
        type: BookNoteMemoType.photo,
        imageChange: MemoImageChange.replaced,
      ),
      localImagePath: 'memo_images/memo_2.jpg',
    );

    final applied = await dao.confirmNoteMemoSynced(
      localId: memo.id,
      serverId: 900,
      capturedUpdatedAt: memo.updatedAt,
      memoType: BookNoteMemoType.photo,
      startPage: null,
      endPage: null,
      content: null,
      imageUrl: 'https://cdn.example.com/notes/400/uploaded.jpg',
      isImportant: false,
      sortOrder: 0,
    );

    expect(applied, isTrue);
    final synced = (await dao.getAllMemosForNote(note.id)).single;
    expect(synced.isDirty, isFalse);
    expect(synced.imageUrl, 'https://cdn.example.com/notes/400/uploaded.jpg');
    expect(synced.localImagePath, 'memo_images/memo_2.jpg');
  });
}
