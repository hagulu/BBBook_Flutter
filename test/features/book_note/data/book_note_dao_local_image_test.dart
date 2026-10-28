import 'dart:io';

import 'package:bbbook/core/policy/attachment_limit_policy.dart';
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

  // 로컬 → 서버 저장 전환은 Import 첨부 응답의 R2 키를 그대로 저장하고,
  // 이후 동기화는 같은 사진을 전체 공개 URL로 내려준다.
  test('전환 때 저장한 R2 키가 같은 사진의 공개 URL로 동기화돼도 로컬 사본을 유지한다', () async {
    const r2Key = 'prod/notes/400/imports/12/photo-a.jpg';
    await applyServerPhoto(imageUrl: r2Key);
    await dao.setLocalImagePath(
      localId: (await readMemo()).id,
      localImagePath: 'memo_images/local_1.jpg',
      expectedImageUrl: r2Key,
    );

    await applyServerPhoto(imageUrl: 'https://cdn.example.com/$r2Key');

    final memo = await readMemo();
    expect(memo.localImagePath, 'memo_images/local_1.jpg');
    expect(memo.imageUrl, 'https://cdn.example.com/$r2Key');
  });

  test('전환 때 저장한 R2 키와 다른 사진이 동기화되면 로컬 사본 참조를 끊는다', () async {
    const r2Key = 'prod/notes/400/imports/12/photo-a.jpg';
    await applyServerPhoto(imageUrl: r2Key);
    await dao.setLocalImagePath(
      localId: (await readMemo()).id,
      localImagePath: 'memo_images/local_1.jpg',
      expectedImageUrl: r2Key,
    );

    await applyServerPhoto(
      imageUrl: 'https://cdn.example.com/prod/notes/400/photo-b.jpg',
    );

    expect((await readMemo()).localImagePath, isNull);
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

  group('노트 이미지 한도 원자적 재검사', () {
    const limit = 2;

    Future<BookNote> createNoteWithPhotoMemos(int photoCount) async {
      final note = await dao.createNote(
        ownerUserId: 7,
        userBookId: 20,
        title: null,
      );
      for (var i = 0; i < photoCount; i++) {
        await dao.createNoteMemo(
          ownerUserId: 7,
          userBookId: 20,
          noteId: note.id,
          draft: const BookNoteMemoDraft(
            type: BookNoteMemoType.photo,
            imageChange: MemoImageChange.replaced,
          ),
          localImagePath: 'memo_images/seed_$i.jpg',
          noteImageLimit: limit,
        );
      }
      return note;
    }

    test('편집 화면을 연 뒤 다른 곳에서 채워진 한도는 실제 생성 시점에 다시 걸린다', () async {
      // 편집 화면이 스냅샷을 읽은 뒤(예: 개수 0) 백그라운드 동기화 등으로
      // 노트가 이미 한도만큼 채워진 상태를 흉내낸다.
      final note = await createNoteWithPhotoMemos(limit);

      expect(
        () => dao.createNoteMemo(
          ownerUserId: 7,
          userBookId: 20,
          noteId: note.id,
          draft: const BookNoteMemoDraft(
            type: BookNoteMemoType.photo,
            imageChange: MemoImageChange.replaced,
          ),
          localImagePath: 'memo_images/new.jpg',
          noteImageLimit: limit,
        ),
        throwsA(isA<NoteImageLimitExceededException>()),
      );
      // 실패한 시도는 아무 것도 남기지 않는다(rawQuery로 재확인).
      final count = (await dao.getAllMemosForNote(note.id)).length;
      expect(count, limit);
    });

    test('이미 한도에 도달해도 기존 이미지가 있던 메모의 교체는 통과한다', () async {
      final note = await createNoteWithPhotoMemos(limit);
      final target = (await dao.getAllMemosForNote(note.id)).first;

      final updated = await dao.updateNoteMemo(
        ownerUserId: 7,
        userBookId: 20,
        noteId: note.id,
        noteMemoId: target.id,
        draft: const BookNoteMemoDraft(
          type: BookNoteMemoType.photo,
          imageChange: MemoImageChange.replaced,
        ),
        localImagePath: 'memo_images/replacement.jpg',
        noteImageLimit: limit,
      );

      expect(updated.localImagePath, 'memo_images/replacement.jpg');
    });

    test('이미 한도에 도달했으면 텍스트 메모를 사진으로 전환해 새 이미지를 추가할 수 없다', () async {
      final note = await createNoteWithPhotoMemos(limit);
      final textMemo = await dao.createNoteMemo(
        ownerUserId: 7,
        userBookId: 20,
        noteId: note.id,
        draft: const BookNoteMemoDraft(
          type: BookNoteMemoType.thought,
          content: '텍스트 메모',
        ),
        localImagePath: null,
        // 이 생성 자체는 이미지가 없으므로 한도 검사 대상이 아니다.
        noteImageLimit: limit,
      );

      expect(
        () => dao.updateNoteMemo(
          ownerUserId: 7,
          userBookId: 20,
          noteId: note.id,
          noteMemoId: textMemo.id,
          draft: const BookNoteMemoDraft(
            type: BookNoteMemoType.photo,
            imageChange: MemoImageChange.replaced,
          ),
          localImagePath: 'memo_images/converted.jpg',
          noteImageLimit: limit,
        ),
        throwsA(isA<NoteImageLimitExceededException>()),
      );
    });

    test('사진을 지우는 수정은 한도와 무관하게 항상 통과한다', () async {
      final note = await createNoteWithPhotoMemos(limit);
      final target = (await dao.getAllMemosForNote(note.id)).first;

      final cleared = await dao.updateNoteMemo(
        ownerUserId: 7,
        userBookId: 20,
        noteId: note.id,
        noteMemoId: target.id,
        draft: const BookNoteMemoDraft(
          type: BookNoteMemoType.thought,
          content: '사진 제거',
          imageChange: MemoImageChange.cleared,
        ),
        localImagePath: null,
        noteImageLimit: limit,
      );

      expect(cleared.localImagePath, isNull);
    });

    /// 서버 노트 400에 PHOTO 메모들을 동기화로 반영한다. 동기화는 한도를
    /// 검사하지 않으므로 한도를 넘긴 상태도 만들 수 있다.
    Future<List<BookNoteMemo>> applyServerPhotos(
      List<String?> imageUrls,
    ) async {
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
          for (var i = 0; i < imageUrls.length; i++)
            ServerBookNoteMemo(
              id: 500 + i,
              noteId: 400,
              memoType: 'PHOTO',
              startPage: null,
              endPage: null,
              content: null,
              imageUrl: imageUrls[i],
              isImportant: false,
              sortOrder: i,
              createdAt: now,
              updatedAt: now,
            ),
        ],
        deletedNoteMemoIds: const [],
        syncedAt: now,
      );
      return dao.getAllMemosForNote(400);
    }

    // 서버 `images/count`는 Import로 만들어져 아직 이미지가 연결되지 않은
    // PHOTO 메모도 센다 — 로컬이 이미지 유무만 세면 서버가 거절할 저장을
    // 통과시킨다.
    test('이미지가 아직 연결되지 않은 PHOTO 메모도 한도에 포함된다', () async {
      final memos = await applyServerPhotos([
        null,
        'https://cdn.example.com/notes/400/photo-a.jpg',
      ]);
      final pending = memos.firstWhere((memo) => memo.imageUrl == null);
      expect(pending.hasImage, isFalse);
      expect(pending.countsTowardNoteImageLimit, isTrue);

      expect(
        () => dao.createNoteMemo(
          ownerUserId: 7,
          userBookId: 20,
          noteId: 400,
          draft: const BookNoteMemoDraft(
            type: BookNoteMemoType.photo,
            imageChange: MemoImageChange.replaced,
          ),
          localImagePath: 'memo_images/new.jpg',
          noteImageLimit: limit,
        ),
        throwsA(isA<NoteImageLimitExceededException>()),
      );
    });

    test('삭제된 PHOTO 메모는 한도에서 제외된다', () async {
      final note = await createNoteWithPhotoMemos(limit);
      final target = (await dao.getAllMemosForNote(note.id)).first;
      await dao.deleteNoteMemo(
        ownerUserId: 7,
        userBookId: 20,
        noteId: note.id,
        noteMemoId: target.id,
      );

      final created = await dao.createNoteMemo(
        ownerUserId: 7,
        userBookId: 20,
        noteId: note.id,
        draft: const BookNoteMemoDraft(
          type: BookNoteMemoType.photo,
          imageChange: MemoImageChange.replaced,
        ),
        localImagePath: 'memo_images/after_delete.jpg',
        noteImageLimit: limit,
      );

      expect(created.localImagePath, 'memo_images/after_delete.jpg');
    });

    test('한도를 넘긴 상태에서도 이미 자리를 차지한 PHOTO 메모에는 사진을 붙일 수 있다', () async {
      final memos = await applyServerPhotos([
        'https://cdn.example.com/notes/400/photo-a.jpg',
        'https://cdn.example.com/notes/400/photo-b.jpg',
        null,
      ]);
      final pending = memos.firstWhere((memo) => memo.imageUrl == null);

      final updated = await dao.updateNoteMemo(
        ownerUserId: 7,
        userBookId: 20,
        noteId: 400,
        noteMemoId: pending.id,
        draft: const BookNoteMemoDraft(
          type: BookNoteMemoType.photo,
          imageChange: MemoImageChange.replaced,
        ),
        localImagePath: 'memo_images/attached.jpg',
        noteImageLimit: limit,
      );

      expect(updated.localImagePath, 'memo_images/attached.jpg');
    });
  });
}
