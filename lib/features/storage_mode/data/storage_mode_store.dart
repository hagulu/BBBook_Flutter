import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';

import '../../auth/models/standalone_session.dart';
import '../../bookshelf/data/bookshelf_database.dart';

/// 기록을 어디에 원본으로 두는지.
enum StorageMode {
  /// 기본값. 서버가 원본이고 로컬은 그 사본 + 아직 push되지 않은 편집을
  /// 담는다(기존 동기화 구조).
  server('SERVER'),

  /// 기기 로컬이 원본. 서버로 기록·이미지를 올리지 않고 서버에서 내려받지도
  /// 않는다. 서버 → 로컬 이전([LocalStorageMigrationService])을 마쳐야만
  /// 이 모드가 된다.
  local('LOCAL');

  const StorageMode(this.dbValue);

  final String dbValue;

  static StorageMode fromDb(String? value) {
    return StorageMode.values.firstWhere(
      (mode) => mode.dbValue == value,
      orElse: () => StorageMode.server,
    );
  }
}

/// 저장 모드를 읽고 쓰는 단일 창구.
///
/// 동기화·push 경로가 매번 DB를 읽지 않도록 값을 메모리에 캐시한다. 캐시는
/// 이 클래스를 통한 쓰기와 [invalidateCache](로그아웃 등 DB가 통째로 비워질
/// 때)로만 갱신되므로, DB를 직접 건드리는 코드는 두지 않는다.
///
/// 저장 위치는 책장 로컬 DB의 `storage_mode` 테이블이다. 자발적 로그아웃이
/// 실행하는 [BookshelfDatabase.clearAll]이 이 행도 지워, 로컬 데이터가
/// 사라지는 순간 모드도 함께 기본값(서버)으로 돌아간다.
class StorageModeStore {
  StorageModeStore();

  StorageMode? _cached;
  int? _cachedOwnerUserId;
  bool _cachedServerDeletePending = false;

  /// 현재 저장 모드. 캐시가 없으면 DB에서 읽어 채운다.
  Future<StorageMode> current() async {
    final cached = _cached;
    if (cached != null) return cached;
    final row = await _readRow();
    _cached = StorageMode.fromDb(row?['mode'] as String?);
    _cachedOwnerUserId = row?['owner_user_id'] as int?;
    _cachedServerDeletePending = (row?['server_delete_pending'] as int?) == 1;
    return _cached!;
  }

  Future<bool> isLocal() async => await current() == StorageMode.local;

  /// 이 로컬 데이터의 주인. 로컬 저장 모드에서 다른 계정이 로그인했는지
  /// 판별하는 데 쓴다([StorageModeStore] 사용처 참고).
  Future<int?> ownerUserId() async {
    await current();
    return _cachedOwnerUserId;
  }

  /// 서버 기록 정리가 아직 남아 있는지. 전환 직후 삭제가 실패했거나 앱이
  /// 종료된 경우 true로 남아, 프로필에서 다시 정리할 수 있게 한다.
  Future<bool> isServerDeletePending() async {
    await current();
    return _cached == StorageMode.local && _cachedServerDeletePending;
  }

  /// 이 로컬 데이터가 계정 없이 쓰는 사용자가 만든 것인지.
  Future<bool> isStandaloneOwned() async {
    await current();
    return _cached == StorageMode.local &&
        _cachedOwnerUserId == standaloneOwnerUserId;
  }

  /// 로그인 없이 사용하기로 진입하거나, 로컬 저장 모드에서 로그아웃하며 기록만
  /// 남길 때 호출한다.
  ///
  /// 서버 정리 대기([isServerDeletePending])는 일부러 해제한다. 그 정리는
  /// 방금 떠난 계정의 서버 기록을 지우는 작업이라 계정 없이는 실행할 수 없고,
  /// 플래그를 그대로 남기면 다음에 **다른 계정**이 로그인했을 때 그 계정의
  /// 서버 기록을 지우자고 안내하게 된다.
  /// [alongside]를 넘기면 그 쓰기와 이 행 갱신이 한 트랜잭션에서 함께 커밋된다
  /// ([_write] 참고).
  Future<void> switchToStandalone({
    Future<void> Function(Transaction txn)? alongside,
  }) async {
    await _write(
      StorageMode.local,
      standaloneOwnerUserId,
      serverDeletePending: false,
      alongside: alongside,
    );
    developer.log('[저장 모드 전환] mode=LOCAL owner=STANDALONE result=SUCCESS');
  }

  /// 로컬 저장 모드를 유지한 채 소유자만 바꾼다.
  ///
  /// 계정 없이 쓰던 기록을 로그인 계정이 그대로 이어받는 전환 전용이다. 그
  /// 경로의 행은 [switchToStandalone]이 써서 서버 정리 대기가 항상 false이므로
  /// 아래에서 그 값을 그대로 옮겨도 안전하다 — 다른 곳에서 부르면 이전 계정의
  /// 정리 대기가 새 계정으로 따라붙어, 그 계정의 서버 기록을 지우자고 안내하게
  /// 된다.
  ///
  /// 모드가 로컬이 아니면(서버 저장) 아무 것도 하지 않는다 — 서버 모드에는
  /// 소유자 행 자체가 없는 것이 정상이다.
  /// [alongside]를 넘기면 그 쓰기와 이 행 갱신이 한 트랜잭션에서 함께 커밋된다
  /// ([_write] 참고).
  Future<void> adoptOwner(
    int ownerUserId, {
    Future<void> Function(Transaction txn)? alongside,
  }) async {
    if (await current() != StorageMode.local) return;
    await _write(
      StorageMode.local,
      ownerUserId,
      serverDeletePending: _cachedServerDeletePending,
      alongside: alongside,
    );
    developer.log('[저장 모드 소유자 변경] userId=$ownerUserId result=SUCCESS');
  }

  /// 서버 → 로컬 이전에서 이미지 확보까지 끝낸 뒤 호출한다. 이 시점부터
  /// 동기화·push가 멈추므로, 서버 데이터 삭제보다 **먼저** 기록해야 한다 —
  /// 순서가 반대면 삭제 직후 앱이 죽었을 때 다음 동기화가 "서버에서 지워진
  /// 기록"으로 판단해 로컬 원본까지 지운다. 아직 서버 정리 전이라
  /// [isServerDeletePending]은 true로 남는다.
  Future<void> switchToLocal({required int ownerUserId}) async {
    await _write(StorageMode.local, ownerUserId, serverDeletePending: true);
    developer.log('[저장 모드 전환] mode=LOCAL userId=$ownerUserId result=SUCCESS');
  }

  /// 서버 기록 일괄 소프트 삭제가 성공한 뒤 호출한다.
  Future<void> markServerRecordsDeleted() async {
    final ownerUserId = await this.ownerUserId();
    if (ownerUserId == null) return;
    await _write(StorageMode.local, ownerUserId, serverDeletePending: false);
    developer.log('[서버 기록 정리] result=SUCCESS');
  }

  /// 로컬 데이터를 비울 때(다른 계정 로그인 등) 기본값으로 되돌린다.
  ///
  /// [alongside]를 넘기면 그 쓰기와 이 행 삭제가 한 트랜잭션에서 함께
  /// 커밋된다 — 계정 없이 둘러보기만 하다 로그인하는 경로에서 standalone
  /// 세션 표시([LocalAuthStore.endStandaloneSessionIn])와 함께 묶어, 둘 중
  /// 하나만 반영된 채 앱이 죽어 저장 모드는 서버인데 standalone 표시는
  /// 남는 조합이 생기지 않게 한다.
  Future<void> resetToServer({
    Future<void> Function(Transaction txn)? alongside,
  }) async {
    final db = await BookshelfDatabase.instance();
    if (alongside == null) {
      await db.delete('storage_mode');
    } else {
      await db.transaction((txn) async {
        await alongside(txn);
        await txn.delete('storage_mode');
      });
    }
    _cached = StorageMode.server;
    _cachedOwnerUserId = null;
    _cachedServerDeletePending = false;
  }

  /// [BookshelfDatabase.clearAll]처럼 DB를 통째로 비운 뒤 호출한다.
  void invalidateCache() {
    _cached = null;
    _cachedOwnerUserId = null;
    _cachedServerDeletePending = false;
  }

  Future<Map<String, Object?>?> _readRow() async {
    final db = await BookshelfDatabase.instance();
    final rows = await db.query('storage_mode', limit: 1);
    return rows.isEmpty ? null : rows.single;
  }

  /// [alongside]는 이 행과 **같은 트랜잭션**에서 실행할 쓰기다.
  ///
  /// 소유자를 바꿀 때 기록(`book_note`/`book_reflection`)의 `owner_user_id`와
  /// 세션 표시(`sync_meta`)를 함께 넘겨, 셋 중 일부만 바뀐 상태가 남지 않게
  /// 한다 — 그 상태가 되면 조회 기준(소유자)과 실제 행이 어긋나 노트·독후감이
  /// 통째로 보이지 않는다. 메모리 캐시는 커밋이 끝난 뒤에만 갱신한다.
  Future<void> _write(
    StorageMode mode,
    int ownerUserId, {
    required bool serverDeletePending,
    Future<void> Function(Transaction txn)? alongside,
  }) async {
    final db = await BookshelfDatabase.instance();
    final row = {
      'id': 1,
      'mode': mode.dbValue,
      'owner_user_id': ownerUserId,
      'server_delete_pending': serverDeletePending ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (alongside == null) {
      await db.insert(
        'storage_mode',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.transaction((txn) async {
        await alongside(txn);
        await txn.insert(
          'storage_mode',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    }
    _cached = mode;
    _cachedOwnerUserId = ownerUserId;
    _cachedServerDeletePending = serverDeletePending;
  }
}

/// 앱 전역에서 공유하는 기본 인스턴스(테스트는 생성자로 별도 인스턴스를 만든다).
final storageModeStore = StorageModeStore();
