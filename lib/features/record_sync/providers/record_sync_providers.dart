import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../data/record_sync_api.dart';
import '../data/record_sync_dao.dart';
import '../data/record_sync_repository.dart';

enum InitialRecordSyncPhase { checking, downloading, saving, completed, failed }

class InitialRecordSyncState {
  const InitialRecordSyncState({
    required this.phase,
    this.saved = 0,
    this.total = 0,
  });

  final InitialRecordSyncPhase phase;
  final int saved;
  final int total;

  double? get progress {
    if (phase != InitialRecordSyncPhase.saving) return null;
    if (total == 0) return 1;
    return saved / total;
  }
}

final recordSyncApiProvider = Provider<RecordSyncApi>((ref) {
  return RecordSyncApi(ref.watch(apiClientProvider));
});

final recordSyncRepositoryProvider = Provider<RecordSyncRepository>((ref) {
  return RecordSyncRepository(ref.watch(recordSyncApiProvider));
});

class InitialRecordSyncController
    extends AutoDisposeFamilyNotifier<InitialRecordSyncState, int> {
  late RecordSyncRepository _repository;
  bool _disposed = false;
  Future<void>? _inFlight;

  @override
  InitialRecordSyncState build(int userId) {
    _repository = ref.watch(recordSyncRepositoryProvider);
    ref.onDispose(() => _disposed = true);
    Future.microtask(() => _initialize(userId));
    return const InitialRecordSyncState(phase: InitialRecordSyncPhase.checking);
  }

  Future<void> retry() {
    if (_disposed) return Future<void>.value();
    return _startSync(arg);
  }

  Future<void> _initialize(int userId) async {
    try {
      // 로컬 저장 모드에서는 서버에서 내려받을 기록이 없다(전환 시점에
      // 모두 로컬로 옮기고 서버 기록은 정리했다).
      if (await ref.read(storageModeStoreProvider).isLocal() ||
          await _repository.isInitialSyncCompleted(userId)) {
        if (!_disposed) {
          state = const InitialRecordSyncState(
            phase: InitialRecordSyncPhase.completed,
          );
        }
        return;
      }
      await _startSync(userId);
    } catch (_) {
      if (!_disposed) {
        state = const InitialRecordSyncState(
          phase: InitialRecordSyncPhase.failed,
        );
      }
    }
  }

  Future<void> _startSync(int userId) {
    return _inFlight ??= _runSync(userId).whenComplete(() => _inFlight = null);
  }

  Future<void> _runSync(int userId) async {
    try {
      await _repository.synchronize(
        userId: userId,
        onDownloadStarted: () {
          if (!_disposed) {
            state = const InitialRecordSyncState(
              phase: InitialRecordSyncPhase.downloading,
            );
          }
        },
        onSaveProgress: (saved, total) {
          if (!_disposed) {
            state = InitialRecordSyncState(
              phase: InitialRecordSyncPhase.saving,
              saved: saved,
              total: total,
            );
          }
        },
      );
      if (!_disposed) {
        state = const InitialRecordSyncState(
          phase: InitialRecordSyncPhase.completed,
        );
      }
    } on RecordSyncSessionChanged {
      // 로그아웃/계정 전환으로 폐기되는 정상 경로다. 이전 세션의 실패 UI를
      // 새 세션에 남기지 않는다.
    } catch (_) {
      if (!_disposed) {
        state = const InitialRecordSyncState(
          phase: InitialRecordSyncPhase.failed,
        );
      }
    }
  }
}

final initialRecordSyncControllerProvider = NotifierProvider.autoDispose
    .family<InitialRecordSyncController, InitialRecordSyncState, int>(
      InitialRecordSyncController.new,
    );
