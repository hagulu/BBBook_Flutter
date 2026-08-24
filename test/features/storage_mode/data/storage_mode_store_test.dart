import 'dart:io';

import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/storage_mode/data/storage_mode_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 저장 모드의 영속성과 초기화 규칙 테스트.
///
/// 모드가 잘못 남으면 로컬 원본을 서버 동기화가 지우거나(로컬인데 서버로
/// 읽힘) 반대로 서버 사용자의 동기화가 멈춘다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    await db.delete('storage_mode');
  });

  test('기본값은 서버 저장이다', () async {
    final store = StorageModeStore();

    expect(await store.current(), StorageMode.server);
    expect(await store.isLocal(), isFalse);
    expect(await store.ownerUserId(), isNull);
  });

  test('로컬 전환은 소유자와 함께 저장되고 다시 읽어도 유지된다', () async {
    await StorageModeStore().switchToLocal(ownerUserId: 42);

    // 앱을 다시 켠 것과 같은 상태(캐시 없는 새 인스턴스).
    final reopened = StorageModeStore();
    expect(await reopened.current(), StorageMode.local);
    expect(await reopened.ownerUserId(), 42);
  });

  test('로컬 데이터를 비우면 모드도 서버로 돌아간다', () async {
    final store = StorageModeStore();
    await store.switchToLocal(ownerUserId: 42);

    await store.resetToServer();

    expect(await store.current(), StorageMode.server);
    expect(await StorageModeStore().current(), StorageMode.server);
  });

  test('로그아웃(clearAll)은 모드 행까지 지운다', () async {
    await StorageModeStore().switchToLocal(ownerUserId: 42);

    await BookshelfDatabase.clearAll();

    expect(await StorageModeStore().current(), StorageMode.server);
  });
}
