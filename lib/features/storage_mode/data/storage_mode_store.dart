import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';

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
  Future<void> resetToServer() async {
    final db = await BookshelfDatabase.instance();
    await db.delete('storage_mode');
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

  Future<void> _write(
    StorageMode mode,
    int ownerUserId, {
    required bool serverDeletePending,
  }) async {
    final db = await BookshelfDatabase.instance();
    await db.insert('storage_mode', {
      'id': 1,
      'mode': mode.dbValue,
      'owner_user_id': ownerUserId,
      'server_delete_pending': serverDeletePending ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _cached = mode;
    _cachedOwnerUserId = ownerUserId;
    _cachedServerDeletePending = serverDeletePending;
  }
}

/// 앱 전역에서 공유하는 기본 인스턴스(테스트는 생성자로 별도 인스턴스를 만든다).
final storageModeStore = StorageModeStore();
