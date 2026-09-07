import '../../../core/storage/local_image_store.dart';
import '../../book_note/data/book_note_repository.dart';
import '../../book_reflection/data/book_reflection_repository.dart';
import '../../bookshelf/data/bookshelf_repository.dart';
import '../../record_sync/data/record_sync_api.dart';
import '../../tag/data/tag_repository.dart';
import '../services/local_storage_migration_service.dart';
import 'storage_mode_store.dart';

/// [LocalStorageMigrationSteps]를 기존 동기화 Repository와 API로 구현한다.
///
/// 새 동기화 경로를 만들지 않고 기존 것을 그대로 재사용한다 — 이전은
/// "평소 동기화를 끝까지 한 번 돌리고, 평소에는 미루던 이미지까지 모두
/// 받는 것"이기 때문이다.
class LocalStorageMigrationRepositorySteps
    implements LocalStorageMigrationSteps {
  const LocalStorageMigrationRepositorySteps({
    required this.ownerUserId,
    required this.bookshelfRepository,
    required this.noteRepository,
    required this.reflectionRepository,
    required this.tagRepository,
    required this.recordSyncApi,
    required this.storageMode,
  });

  final int ownerUserId;
  final BookshelfRepository bookshelfRepository;
  final BookNoteRepository noteRepository;
  final BookReflectionRepository reflectionRepository;
  final TagRepository tagRepository;
  final RecordSyncApi recordSyncApi;
  final StorageModeStore storageMode;

  @override
  Future<void> syncAllRecords() async {
    // 책장부터 맞춰야 노트/독후감/태그가 붙을 로컬 책 행이 존재한다. 각
    // sync는 dirty push를 먼저 수행하므로 아직 서버에 올리지 못한 로컬
    // 편집도 이 시점에 함께 반영된다.
    //
    // `POST /api/me/records/import/*`(로컬 → 서버 재전환 Import, §
    // `server_storage_migration`)는 태그(tags/tagMaps)도 함께 보내므로,
    // 로컬 저장 모드에서 추가·삭제한 태그도 서버 재전환 시 그대로
    // 반영된다. 그래도 여기서 태그까지 동기화하는 이유는 전환 *직전*
    // 서버 데이터를 로컬에 최신으로 맞춰야 해서다(재전환 시 태그 반영
    // 여부와는 별개의 목적).
    await bookshelfRepository.sync();
    await noteRepository.sync(ownerUserId: ownerUserId);
    await reflectionRepository.sync(ownerUserId: ownerUserId);
    await tagRepository.sync();
  }

  @override
  Future<LocalImageSyncReport> downloadAllImages(
    void Function(int done, int total) onProgress,
  ) async {
    // 메모 사진과 독후감 이미지의 진행률을 하나로 합쳐 보여준다.
    var memoDone = 0;
    var memoTotal = 0;
    var reflectionDone = 0;
    var reflectionTotal = 0;
    void emit() =>
        onProgress(memoDone + reflectionDone, memoTotal + reflectionTotal);

    final memoReport = await noteRepository.downloadAllImages(
      onProgress: (done, total) {
        memoDone = done;
        memoTotal = total;
        emit();
      },
    );
    final reflectionReport = await reflectionRepository.downloadAllImages(
      onProgress: (done, total) {
        reflectionDone = done;
        reflectionTotal = total;
        emit();
      },
    );
    return memoReport + reflectionReport;
  }

  @override
  Future<int> countMissingLocalImages() async {
    return await noteRepository.countImagesPendingDownload() +
        await reflectionRepository.countImagesPendingDownload();
  }

  @override
  Future<void> switchToLocalMode() =>
      storageMode.switchToLocal(ownerUserId: ownerUserId);

  @override
  Future<void> deleteServerRecords() => recordSyncApi.deleteAllRecords();

  @override
  Future<void> markServerRecordsDeleted() =>
      storageMode.markServerRecordsDeleted();
}
