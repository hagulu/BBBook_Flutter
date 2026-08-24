import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_notifier.dart';
import '../../book_note/providers/book_note_providers.dart';
import '../../book_reflection/providers/book_reflection_providers.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../record_sync/providers/record_sync_providers.dart';
import '../data/local_storage_migration_steps.dart';
import '../data/storage_mode_store.dart';
import '../services/local_storage_migration_service.dart';

final storageModeStoreProvider = Provider<StorageModeStore>((ref) {
  return storageModeStore;
});

/// 현재 저장 모드. 전환이 끝나면 [LocalStorageMigrationController]가
/// 무효화해 화면이 새 값을 읽는다.
final storageModeProvider = FutureProvider<StorageMode>((ref) {
  return ref.watch(storageModeStoreProvider).current();
});

/// 로컬 모드로 전환은 됐지만 서버 기록 정리가 남아 있는지.
/// 전환 직후 삭제 실패·앱 종료로 끊긴 경우 true가 되어, 프로필에서 다시
/// 정리할 수 있게 한다.
final serverDeletePendingProvider = FutureProvider<bool>((ref) {
  return ref.watch(storageModeStoreProvider).isServerDeletePending();
});

/// 이전 전에 사용자에게 보여줄 대략의 다운로드 규모.
///
/// 서버 기록은 이미 로컬에 동기화돼 있으므로 로컬 DB만 세면 된다(전환
/// 안내를 위해 서버에 별도 요청을 보내지 않는다). 동기화 단계에서 새
/// 기록이 더 들어올 수 있어 정확한 수가 아니라 "대략"이다.
final localStorageMigrationPreviewProvider =
    FutureProvider.autoDispose<LocalStorageMigrationPreview>((ref) async {
      final images =
          await ref
              .read(bookNoteRepositoryProvider)
              .countImagesPendingDownload() +
          await ref
              .read(bookReflectionRepositoryProvider)
              .countImagesPendingDownload();
      return LocalStorageMigrationPreview(pendingImages: images);
    });

class LocalStorageMigrationPreview {
  const LocalStorageMigrationPreview({required this.pendingImages});

  /// 아직 이 기기에 없는 서버 이미지 수.
  final int pendingImages;
}

/// 서버 → 로컬 저장 이전 실행/진행 상태.
class LocalStorageMigrationController
    extends AutoDisposeNotifier<LocalStorageMigrationState> {
  Future<void>? _inFlight;
  bool _disposed = false;

  @override
  LocalStorageMigrationState build() {
    ref.onDispose(() => _disposed = true);
    return const LocalStorageMigrationState();
  }

  /// 겹쳐 눌러도 진행 중인 이전을 공유한다(같은 이전을 두 번 돌리지 않는다).
  Future<void> start() {
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  /// 전환은 끝났는데 서버 기록 정리만 남은 상태를 마저 처리한다(멱등한
  /// DELETE라 여러 번 호출해도 안전하다).
  Future<bool> retryServerCleanup() async {
    try {
      await ref.read(recordSyncApiProvider).deleteAllRecords();
      await ref.read(storageModeStoreProvider).markServerRecordsDeleted();
      if (!_disposed) ref.invalidate(serverDeletePendingProvider);
      return true;
    } catch (error) {
      developer.log('[서버 기록 정리] result=FAIL reason=${error.runtimeType}');
      return false;
    }
  }

  Future<void> _run() async {
    final ownerUserId = ref.read(
      authNotifierProvider.select((auth) => auth.user?.id),
    );
    if (ownerUserId == null) return;

    final steps = LocalStorageMigrationRepositorySteps(
      ownerUserId: ownerUserId,
      bookshelfRepository: ref.read(bookshelfRepositoryProvider),
      noteRepository: ref.read(bookNoteRepositoryProvider),
      reflectionRepository: ref.read(bookReflectionRepositoryProvider),
      recordSyncApi: ref.read(recordSyncApiProvider),
      storageMode: ref.read(storageModeStoreProvider),
    );
    final result = await LocalStorageMigrationService(steps).run(
      onProgress: (progress) {
        if (_disposed) return;
        state = progress;
      },
    );
    if (_disposed) return;
    state = result;
    ref.invalidate(serverDeletePendingProvider);
    if (result.stage == LocalStorageMigrationStage.completed) {
      // 이전 중 내려받은 기록/이미지가 화면에 반영되도록 목록을 다시 읽게
      // 하고, 저장 모드 표시도 갱신한다.
      ref.invalidate(storageModeProvider);
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
      ref.read(bookNoteSyncVersionProvider.notifier).state++;
      ref.read(bookReflectionSyncVersionProvider.notifier).state++;
    }
  }
}

final localStorageMigrationControllerProvider =
    AutoDisposeNotifierProvider<
      LocalStorageMigrationController,
      LocalStorageMigrationState
    >(LocalStorageMigrationController.new);
