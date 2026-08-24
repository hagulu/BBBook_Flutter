import 'dart:io';

import 'package:bbbook/features/book_reflection/data/book_reflection_dao.dart';
import 'package:bbbook/features/book_reflection/models/book_reflection.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 독후감 본문 이미지의 "서버 URL ↔ 로컬 사본" 매칭 테이블 테스트.
///
/// 이 테이블은 서버에 없는 로컬 전용 정보라 외래 키를 걸지 않는다 —
/// 그래서 독후감이 사라졌을 때의 정리를 직접 해야 하고, 그걸 빠뜨리면
/// 로컬 이미지 파일이 영원히 지워지지 않는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dao = BookReflectionDao();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
      await txn.delete('reflection_image_local');
      await txn.delete('book_reflection');
    });
  });

  Future<BookReflection> createReflection() {
    return dao.createLocal(
      ownerUserId: 7,
      userBookId: 20,
      draft: const BookReflectionDraft(
        title: '독후감',
        contentJson: {
          'ops': [
            {'insert': '본문\n'},
          ],
        },
        contentText: '본문',
        isPublic: false,
      ),
    );
  }

  test('매칭을 저장하고 서버 URL로 로컬 사본을 찾는다', () async {
    final reflection = await createReflection();

    await dao.replaceLocalImages(
      reflectionId: reflection.id,
      mappings: const {
        'https://cdn.example.com/r/a.jpg': 'reflection_images/remote_a.jpg',
        'https://cdn.example.com/r/b.jpg': 'reflection_images/remote_b.jpg',
      },
    );

    expect(await dao.findLocalImagePaths(reflection.id), {
      'https://cdn.example.com/r/a.jpg': 'reflection_images/remote_a.jpg',
      'https://cdn.example.com/r/b.jpg': 'reflection_images/remote_b.jpg',
    });
  });

  test('본문에서 빠진 이미지의 매칭은 다시 저장할 때 사라진다', () async {
    final reflection = await createReflection();
    await dao.replaceLocalImages(
      reflectionId: reflection.id,
      mappings: const {
        'https://cdn.example.com/r/a.jpg': 'reflection_images/remote_a.jpg',
        'https://cdn.example.com/r/b.jpg': 'reflection_images/remote_b.jpg',
      },
    );

    // b를 지운 본문으로 다시 push된 상황.
    await dao.replaceLocalImages(
      reflectionId: reflection.id,
      mappings: const {
        'https://cdn.example.com/r/a.jpg': 'reflection_images/remote_a.jpg',
      },
    );

    final paths = await dao.findLocalImagePaths(reflection.id);
    expect(paths.keys, ['https://cdn.example.com/r/a.jpg']);
    // 참조가 끊긴 파일은 orphan 정리 대상이 된다.
    expect((await dao.getAllLocalImages()).map((link) => link.localImagePath), [
      'reflection_images/remote_a.jpg',
    ]);
  });

  test('독후감이 사라지면 남은 매칭도 정리된다', () async {
    final kept = await createReflection();
    final removed = await createReflection();
    await dao.replaceLocalImages(
      reflectionId: kept.id,
      mappings: const {
        'https://cdn.example.com/r/a.jpg': 'reflection_images/remote_a.jpg',
      },
    );
    await dao.replaceLocalImages(
      reflectionId: removed.id,
      mappings: const {
        'https://cdn.example.com/r/gone.jpg':
            'reflection_images/remote_gone.jpg',
      },
    );

    // 동기화가 독후감 행만 지운 상황(외래 키가 없어 매칭은 남는다).
    final db = await BookshelfDatabase.instance();
    await db.delete(
      'book_reflection',
      where: 'id = ?',
      whereArgs: [removed.id],
    );
    await dao.deleteOrphanLocalImages();

    expect((await dao.getAllLocalImages()).map((link) => link.reflectionId), [
      kept.id,
    ]);
  });

  test('소프트 삭제된 독후감의 매칭도 정리 대상이다', () async {
    final reflection = await createReflection();
    await dao.replaceLocalImages(
      reflectionId: reflection.id,
      mappings: const {
        'https://cdn.example.com/r/a.jpg': 'reflection_images/remote_a.jpg',
      },
    );

    await dao.markDeletedLocal(
      ownerUserId: 7,
      userBookId: 20,
      reflectionId: reflection.id,
    );
    await dao.deleteOrphanLocalImages();

    expect(await dao.getAllLocalImages(), isEmpty);
  });

  test('hydration 대상 조회는 삭제되지 않은 독후감만 돌려준다', () async {
    final active = await createReflection();
    final deleted = await createReflection();
    await dao.markDeletedLocal(
      ownerUserId: 7,
      userBookId: 20,
      reflectionId: deleted.id,
    );

    expect((await dao.getAllActive()).map((reflection) => reflection.id), [
      active.id,
    ]);
  });
}
