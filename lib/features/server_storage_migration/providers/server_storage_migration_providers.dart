import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_notifier.dart';
import '../../auth/providers/auth_providers.dart';
import '../../book_note/data/book_note_dao.dart';
import '../../book_note/providers/book_note_providers.dart';
import '../../book_reflection/data/book_reflection_dao.dart';
import '../../book_reflection/providers/book_reflection_providers.dart';
import '../../bookshelf/data/bookshelf_dao.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../record_sync/providers/record_sync_providers.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../../tag/data/tag_dao.dart';
import '../../tag/providers/tag_providers.dart';
import '../data/record_import_api.dart';
import '../data/server_storage_migration_repository_steps.dart';
import '../services/server_storage_migration_service.dart';

final recordImportApiProvider = Provider<RecordImportApi>((ref) {
  return RecordImportApi(ref.read(apiClientProvider));
});

/// 로컬 → 서버 저장 이전 실행/진행 상태.
class ServerStorageMigrationController
    extends AutoDisposeNotifier<ServerStorageMigrationState> {
  Future<void>? _inFlight;
  bool _disposed = false;

  @override
  ServerStorageMigrationState build() {
    ref.onDispose(() => _disposed = true);
    return const ServerStorageMigrationState();
  }

  /// 겹쳐 눌러도 진행 중인 전환을 공유한다(같은 전환을 두 번 돌리지 않는다).
  Future<void> start() {
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  Future<void> _run() async {
    final ownerUserId = ref.read(
      authNotifierProvider.select((auth) => auth.user?.id),
    );
    if (ownerUserId == null) return;

    final steps = ServerStorageMigrationRepositorySteps(
      ownerUserId: ownerUserId,
      bookshelfDao: const BookshelfDao(),
      noteDao: const BookNoteDao(),
      reflectionDao: const BookReflectionDao(),
      tagDao: const TagDao(),
      recordImportApi: ref.read(recordImportApiProvider),
      recordSyncApi: ref.read(recordSyncApiProvider),
      storageMode: ref.read(storageModeStoreProvider),
    );
    final result = await ServerStorageMigrationService(steps).run(
      onProgress: (progress) {
        if (_disposed) return;
        state = progress;
      },
    );
    if (_disposed) return;
    state = result;
    if (result.stage == ServerStorageMigrationStage.completed) {
      // 전환 중 서버에 새로 반영된 서버 ID·이미지가 화면에 보이도록 목록을
      // 다시 읽게 하고, 저장 모드 표시도 갱신한다.
      ref.invalidate(storageModeProvider);
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
      ref.read(bookNoteSyncVersionProvider.notifier).state++;
      ref.read(bookReflectionSyncVersionProvider.notifier).state++;
      // Import API는 태그(tags/tagMaps)를 새로 만들거나 재사용할 뿐 삭제를
      // 표현하지 못한다 — 로컬 저장 모드 동안 사용자가 지운 태그 매핑은
      // Import에 실려 가지 않고 로컬에 `is_dirty=1`로만 남는다. 평소
      // 태그 동기화(dirty push + 재조회, 실패해도 예외 없이 dirty로 남아
      // 조용히 재시도된다 — `TagSyncController._runSync`)를 여기서 곧바로
      // 기다려 실행해야, 화면이 "전환 완료"를 보여주는 시점에는 그 삭제가
      // 이미 서버에(그리고 다른 기기에도) 반영된 상태다.
      await ref.read(tagSyncControllerProvider.notifier).syncNow();
    }
  }
}

final serverStorageMigrationControllerProvider =
    AutoDisposeNotifierProvider<
      ServerStorageMigrationController,
      ServerStorageMigrationState
    >(ServerStorageMigrationController.new);
