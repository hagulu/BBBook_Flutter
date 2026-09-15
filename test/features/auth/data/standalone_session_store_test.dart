import 'dart:convert';
import 'dart:io';

import 'package:bbbook/features/auth/data/local_auth_store.dart';
import 'package:bbbook/features/auth/models/auth_user.dart';
import 'package:bbbook/features/auth/models/standalone_session.dart';
import 'package:bbbook/features/bookshelf/data/bookshelf_database.dart';
import 'package:bbbook/features/storage_mode/data/storage_mode_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 계정 없이 쓰는 사용자("로그인 없이 사용하기")의 로컬 상태 규칙 테스트.
///
/// 이 세 가지가 어긋나면 완료 조건이 바로 깨진다.
/// - 앱을 다시 켰을 때 그 상태로 돌아오는가(`standalone_session_active`).
/// - 로컬 기록이 그 사용자 소유로 격리되고, 로그인 시 계정 소유로 옮겨지는가.
/// - 계정 없는 기록만 있는 기기가 존재하지 않는 계정으로 복원되지 않는가.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = LocalAuthStore();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 테스트 파일은 병렬 실행되므로 파일마다 별도 DB 경로를 쓴다.
    final databaseDirectory = await Directory.systemTemp.createTemp(
      'bookshelf_standalone_test',
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
      await txn.delete('book_reflection');
      await txn.delete('user_book');
      await txn.delete('sync_meta');
      await txn.delete('storage_mode');
    });
    StorageModeStore().invalidateCache();
  });

  Future<void> insertNote({
    required int ownerUserId,
    int userBookId = 1,
  }) async {
    final db = await BookshelfDatabase.instance();
    final now = DateTime.utc(2026, 9, 1).toIso8601String();
    await db.insert('book_note', {
      'owner_user_id': ownerUserId,
      'user_book_id': userBookId,
      'title': '노트',
      'created_at': now,
      'updated_at': now,
      'is_dirty': 1,
    });
  }

  Future<void> insertReflection({
    required int ownerUserId,
    int userBookId = 1,
  }) async {
    final db = await BookshelfDatabase.instance();
    final now = DateTime.utc(2026, 9, 1).toIso8601String();
    await db.insert('book_reflection', {
      'owner_user_id': ownerUserId,
      'user_book_id': userBookId,
      'reflection_type': 'REFLECTION',
      'title': '독후감',
      'content_json': '{}',
      'is_public': 0,
      'created_at': now,
      'updated_at': now,
      'is_dirty': 1,
    });
  }

  Future<List<int>> ownerIds(String table) async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query(table, columns: ['owner_user_id']);
    return rows.map((row) => row['owner_user_id'] as int).toList();
  }

  group('진입 상태 유지', () {
    test('세션 표시를 남기면 앱을 다시 켜도 계정 없는 상태로 복원된다', () async {
      await store.startStandaloneSession();

      expect(await store.isStandaloneSessionActive(), isTrue);
    });

    test('세션 표시를 지우면 계정 없는 상태로 돌아가지 않는다(로그아웃 직후)', () async {
      await store.startStandaloneSession();

      await store.endStandaloneSession();

      expect(await store.isStandaloneSessionActive(), isFalse);
    });

    test('서버 동기화 모드 로그아웃(clearAll)은 세션 표시까지 지운다', () async {
      await store.startStandaloneSession();

      await BookshelfDatabase.clearAll();

      expect(await store.isStandaloneSessionActive(), isFalse);
    });
  });

  group('저장 모드', () {
    test('계정 없이 시작하면 로컬 저장 모드가 되고 정리할 서버 기록은 없다', () async {
      final mode = StorageModeStore();

      await mode.switchToStandalone();

      expect(await mode.current(), StorageMode.local);
      expect(await mode.isStandaloneOwned(), isTrue);
      expect(await mode.isServerDeletePending(), isFalse);
      // 앱을 다시 켠 것과 같은 상태(캐시 없는 새 인스턴스).
      expect(await StorageModeStore().isStandaloneOwned(), isTrue);
    });

    test('로그인하면 로컬 저장 모드를 유지한 채 소유자만 계정으로 바뀐다', () async {
      final mode = StorageModeStore();
      await mode.switchToStandalone();

      await mode.adoptOwner(42);

      expect(await mode.current(), StorageMode.local);
      expect(await mode.ownerUserId(), 42);
      expect(await mode.isStandaloneOwned(), isFalse);
    });

    test('서버 저장 모드에서는 소유자를 심지 않는다', () async {
      final mode = StorageModeStore();

      await mode.adoptOwner(42);

      expect(await mode.current(), StorageMode.server);
      expect(await mode.ownerUserId(), isNull);
    });

    test('로컬 전환(동기화 끄기)의 서버 정리 대기 상태는 소유자를 바꿔도 유지된다', () async {
      final mode = StorageModeStore();
      await mode.switchToLocal(ownerUserId: 7);

      await mode.adoptOwner(9);

      expect(await mode.isServerDeletePending(), isTrue);
    });

    test('계정을 떼어내면 서버 정리 대기 상태는 해제한다(다른 계정 기록 삭제 방지)', () async {
      final mode = StorageModeStore();
      await mode.switchToLocal(ownerUserId: 7);

      await mode.switchToStandalone();

      expect(await mode.isServerDeletePending(), isFalse);
      expect(await mode.isStandaloneOwned(), isTrue);
    });
  });

  group('기록 소유자 이관', () {
    test('로그인하면 계정 없이 남긴 노트·독후감이 그대로 계정 소유가 된다', () async {
      await insertNote(ownerUserId: standaloneOwnerUserId);
      await insertReflection(ownerUserId: standaloneOwnerUserId);

      await store.rekeyRecordOwner(from: standaloneOwnerUserId, to: 42);

      expect(await ownerIds('book_note'), [42]);
      expect(await ownerIds('book_reflection'), [42]);
    });

    test('로컬 저장 모드 로그아웃은 계정 기록을 지우지 않고 소유자만 떼어낸다', () async {
      await insertNote(ownerUserId: 42);
      await insertReflection(ownerUserId: 42);

      await store.rekeyRecordOwner(from: 42, to: standaloneOwnerUserId);

      expect(await ownerIds('book_note'), [standaloneOwnerUserId]);
      expect(await ownerIds('book_reflection'), [standaloneOwnerUserId]);
    });

    test('인증이 먼저 풀려 소유자를 모르면 저장 모드의 소유자로 찾아 떼어낸다', () async {
      // 로그아웃 시 `state.user`가 비어 있는 경우(인증 만료 후 로그아웃).
      final mode = StorageModeStore();
      await mode.switchToLocal(ownerUserId: 42);
      await insertNote(ownerUserId: 42);

      final ownerUserId = await mode.ownerUserId();
      await store.rekeyRecordOwner(
        from: ownerUserId!,
        to: standaloneOwnerUserId,
      );

      expect(await ownerIds('book_note'), [standaloneOwnerUserId]);
    });

    test('소유자·저장 모드·세션 표시가 한 트랜잭션으로 함께 반영된다', () async {
      final mode = StorageModeStore();
      await mode.switchToStandalone();
      await store.startStandaloneSession();
      await insertNote(ownerUserId: standaloneOwnerUserId);

      await mode.adoptOwner(
        42,
        alongside: (txn) async {
          await store.rekeyRecordOwnerIn(
            txn,
            from: standaloneOwnerUserId,
            to: 42,
          );
          await store.endStandaloneSessionIn(txn);
        },
      );

      expect(await ownerIds('book_note'), [42]);
      expect(await mode.ownerUserId(), 42);
      expect(await store.isStandaloneSessionActive(), isFalse);
    });

    test('트랜잭션 중간에 실패하면 저장 모드와 기록 모두 이전 상태로 남는다', () async {
      // 일부만 반영되면 조회 기준(소유자)과 실제 행이 어긋나 노트·독후감이
      // 통째로 보이지 않는다 — 앱이 중간에 종료되는 경우와 같은 상황이다.
      final mode = StorageModeStore();
      await mode.switchToStandalone();
      await store.startStandaloneSession();
      await insertNote(ownerUserId: standaloneOwnerUserId);

      await expectLater(
        mode.adoptOwner(
          42,
          alongside: (txn) async {
            await store.rekeyRecordOwnerIn(
              txn,
              from: standaloneOwnerUserId,
              to: 42,
            );
            throw StateError('중간 실패');
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(await ownerIds('book_note'), [standaloneOwnerUserId]);
      // 캐시가 아니라 DB에서 다시 읽어도 이전 소유자 그대로여야 한다.
      expect(await StorageModeStore().ownerUserId(), standaloneOwnerUserId);
      expect(await store.isStandaloneSessionActive(), isTrue);
    });

    test('다른 계정의 기록은 건드리지 않는다', () async {
      await insertNote(ownerUserId: standaloneOwnerUserId, userBookId: 1);
      await insertNote(ownerUserId: 7, userBookId: 2);

      await store.rekeyRecordOwner(from: standaloneOwnerUserId, to: 42);

      expect((await ownerIds('book_note'))..sort(), [7, 42]);
    });
  });

  group('계정 복원', () {
    test('계정 없이 남긴 기록만 있으면 존재하지 않는 계정으로 복원하지 않는다', () async {
      await StorageModeStore().switchToStandalone();
      await insertNote(ownerUserId: standaloneOwnerUserId);

      expect(await store.readUser(), isNull);
    });

    test('계정 없이 쓰다 로그인한 기록은 그 계정으로 복원된다', () async {
      await StorageModeStore().switchToStandalone();
      await insertNote(ownerUserId: standaloneOwnerUserId);
      await store.rekeyRecordOwner(from: standaloneOwnerUserId, to: 42);
      await StorageModeStore().adoptOwner(42);

      expect((await store.readUser())?.id, 42);
    });

    test('계정 정보를 지우면 저장된 소유자로 복원되지 않는다(로컬 모드 로그아웃)', () async {
      await store.saveUser(
        const AuthUser(
          id: 42,
          nickname: '독자',
          profileImageUrl: null,
          isFinishedBooksPublic: false,
        ),
      );

      await store.clearUser();

      expect(await store.readUser(), isNull);
    });

    test('저장된 계정 정보가 있으면 그대로 읽는다', () async {
      final db = await BookshelfDatabase.instance();
      await db.insert('sync_meta', {
        'key': 'local_auth_user',
        'value': jsonEncode({
          'id': 42,
          'nickname': '독자',
          'profileImageUrl': null,
          'isFinishedBooksPublic': false,
        }),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      expect((await store.readUser())?.nickname, '독자');
    });
  });
}
