import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_notifier.dart';
import '../../auth/providers/auth_providers.dart';
import '../../book_note/providers/book_note_providers.dart';
import '../../book_reflection/providers/book_reflection_providers.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../bookshelf/data/bookshelf_dao.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../server_storage_migration/providers/server_storage_migration_providers.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../../tag/providers/tag_providers.dart';

/// 로컬 화면 진입 후에만 실행한다. 인증 → 부모 책 → 하위 기록 순서로
/// 복구하고, 실행 중인 동기화와 합류한다. 로컬 조회/저장은 기다리지 않는다.
final backgroundRecordSyncProvider = Provider.autoDispose<BackgroundRecordSync>(
  (ref) {
    final sync = BackgroundRecordSync(ref);
    final apiClient = ref.read(apiClientProvider);
    apiClient.onNetworkAvailable = sync.schedule;
    apiClient.prepareRecordSync = sync.beforeNetworkRequest;
    ref.listen(authNotifierProvider.select((state) => state.accessToken), (
      _,
      token,
    ) {
      if (token != null) sync.schedule();
    });
    ref.onDispose(() {
      apiClient.onNetworkAvailable = null;
      apiClient.prepareRecordSync = null;
      sync.dispose();
    });
    sync.start();
    return sync;
  },
);

class BackgroundRecordSync with WidgetsBindingObserver {
  BackgroundRecordSync(this.ref);

  final Ref ref;
  Timer? _timer;
  Future<void>? _inFlight;
  DateTime? _lastAttempt;
  DateTime? _lastSuccess;
  bool _active = true;
  bool _disposed = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => schedule());
    scheduleMicrotask(schedule);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) schedule();
  }

  void schedule() {
    if (_disposed || !_active || _inFlight != null) return;
    if (_lastAttempt case final last?
        when DateTime.now().difference(last) < const Duration(seconds: 15)) {
      return;
    }
    _lastAttempt = DateTime.now();
    _inFlight = _run().whenComplete(() => _inFlight = null);
  }

  /// ISBN 연결·서재 포함 여부·기록 공개 설정 등 의존성 있는 통신 전에
  /// 기존 동기화에 합류하거나
  /// 미전송 변경을 먼저 시도한다. 매 요청마다 전체 동기화를 반복하지 않고
  /// 동일한 성공 시각·dirty 검사·15초 재시도 제한을 공유한다.
  Future<void> beforeNetworkRequest() async {
    // 이미 실행 중이면 그 작업을 계속 진행시키고 요청은 기다리지 않는다.
    // 동기화 내부에서 호출되어도 자기 자신의 완료를 기다리지 않는다.
    if (_disposed || !_active || _migrationRunning || _inFlight != null) return;
    schedule();
    await _inFlight;
  }

  bool get _migrationRunning =>
      ref.read(localStorageMigrationControllerProvider).isRunning ||
      ref.read(serverStorageMigrationControllerProvider).isRunning;

  Future<void> _run() async {
    final generation = BookshelfDatabase.sessionGeneration;
    bool stopped() =>
        _disposed ||
        !_active ||
        BookshelfDatabase.sessionGeneration != generation ||
        _migrationRunning;
    try {
      if (stopped()) return;
      await ref.read(authNotifierProvider.notifier).ensureSession();
      if (stopped() || await ref.read(storageModeStoreProvider).isLocal()) {
        return;
      }
      if (_lastSuccess case final last?
          when DateTime.now().difference(last) < const Duration(minutes: 10)) {
        if (!await _hasPendingChanges()) return;
      }
      if (stopped()) return;
      await ref.read(bookshelfSyncControllerProvider.notifier).syncNow();
      if (stopped() || ref.read(bookshelfSyncControllerProvider).hasError) {
        return;
      }
      await ref.read(bookNoteSyncControllerProvider.notifier).syncNow();
      if (stopped() || ref.read(bookNoteSyncControllerProvider).hasError) {
        return;
      }
      await ref.read(bookReflectionSyncControllerProvider.notifier).syncNow();
      if (stopped() ||
          ref.read(bookReflectionSyncControllerProvider).hasError) {
        return;
      }
      await ref.read(tagSyncControllerProvider.notifier).syncNow();
      if (stopped() || ref.read(tagSyncControllerProvider).hasError) return;
      _lastSuccess = DateTime.now();
    } catch (_) {
      developer.log('[백그라운드 기록 동기화] result=FAIL reason=retry_pending');
    }
  }

  Future<bool> _hasPendingChanges() async {
    if (await const BookshelfDao().hasRetryableChanges()) return true;
    final db = await BookshelfDatabase.instance();
    // 부모 책의 생성이 보류된 하위 기록도 아직 전송할 수 없다.
    // 이런 자식이 있다는 이유로 전체 동기화를 30초마다 반복하지 않는다.
    for (final from in [
      'book_note c JOIN user_book b ON b.user_book_id = c.user_book_id',
      'book_note_memo c JOIN book_note n ON n.id = c.note_id '
          'JOIN user_book b ON b.user_book_id = n.user_book_id',
      'book_reflection c JOIN user_book b ON b.user_book_id = c.user_book_id',
      'user_book_tag_map c JOIN user_book b ON b.user_book_id = c.user_book_id',
    ]) {
      if ((await db.rawQuery(
        'SELECT 1 FROM $from WHERE c.is_dirty = 1 AND b.pending_delete = 0 '
        'AND (b.sync_retry_after IS NULL OR b.sync_retry_after <= ?) LIMIT 1',
        [DateTime.now().toUtc().toIso8601String()],
      )).isNotEmpty) {
        return true;
      }
    }
    return false;
  }
}
