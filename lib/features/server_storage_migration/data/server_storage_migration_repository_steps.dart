import 'dart:io';

import '../../book_note/data/book_note_dao.dart';
import '../../book_reflection/data/book_reflection_dao.dart';
import '../../bookshelf/data/bookshelf_dao.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../record_sync/data/record_sync_api.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import '../../tag/data/tag_dao.dart';
import 'record_import_api.dart';
import 'record_import_payload_builder.dart';
import 'record_import_snapshot.dart';
import 'record_import_snapshot_builder.dart';
import 'server_storage_migration_steps.dart';
import '../models/record_import_models.dart';

/// [ServerStorageMigrationSteps]를 실제 DAO·API로 구현한다.
class ServerStorageMigrationRepositorySteps
    implements ServerStorageMigrationSteps {
  const ServerStorageMigrationRepositorySteps({
    required this.ownerUserId,
    required this.bookshelfDao,
    required this.noteDao,
    required this.reflectionDao,
    required this.tagDao,
    required this.recordImportApi,
    required this.recordSyncApi,
    required this.storageMode,
  });

  final int ownerUserId;
  final BookshelfDao bookshelfDao;
  final BookNoteDao noteDao;
  final BookReflectionDao reflectionDao;
  final TagDao tagDao;
  final RecordImportApi recordImportApi;
  final RecordSyncApi recordSyncApi;
  final StorageModeStore storageMode;

  @override
  Future<bool> ensureNoPendingServerCleanup() async {
    if (!await storageMode.isServerDeletePending()) return true;
    try {
      await recordSyncApi.deleteAllRecords();
      await storageMode.markServerRecordsDeleted();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<RecordImportPreflightOutcome> prepare() {
    return RecordImportSnapshotBuilder(
      ownerUserId: ownerUserId,
      bookshelfDao: bookshelfDao,
      noteDao: noteDao,
      reflectionDao: reflectionDao,
      tagDao: tagDao,
    ).build();
  }

  @override
  Future<RecordImportSession> startSession() => recordImportApi.start();

  @override
  Future<RecordImportChunkResult> uploadChunk(
    int importId,
    RecordImportChunk chunk,
  ) {
    return recordImportApi.uploadItems(importId, chunk.toJson());
  }

  @override
  Future<RecordImportAttachmentResult> uploadMemoImage(
    int importId,
    int memoLocalId,
    File file,
  ) {
    return recordImportApi.uploadAttachment(
      importId: importId,
      entityType: RecordImportAttachmentEntityType.noteMemo,
      localId: memoLocalId,
      file: file,
    );
  }

  @override
  Future<RecordImportAttachmentResult> uploadReflectionImage(
    int importId,
    int reflectionLocalId,
    String placeholder,
    File file,
  ) {
    return recordImportApi.uploadAttachment(
      importId: importId,
      entityType: RecordImportAttachmentEntityType.reflection,
      localId: reflectionLocalId,
      placeholder: placeholder,
      file: file,
    );
  }

  @override
  Future<void> complete(int importId, RecordImportCounts counts) {
    return recordImportApi.complete(importId, counts);
  }

  /// 네 도메인의 확정 반영을 하나의 로컬 트랜잭션으로 묶는다 — 별도
  /// 트랜잭션으로 나눠 실행하면 그 사이 DB 오류나 앱 종료가 끼어들었을 때
  /// "일부 테이블만 서버 ID가 채워진" 상태가 남을 수 있다.
  ///
  /// 다만 이 트랜잭션 자체가 시작되기 *전에*(예: `/complete` 응답을 받은
  /// 직후) 앱이 죽는 경우까지는 막지 못한다 — 그 경우 서버는 이미
  /// Import를 확정했는데 로컬은 여전히 로컬 저장 모드로 남는다. 재시도는
  /// 항상 `/start`로 새 세션을 시작하는데, 그 세션이 다시 만나는 독후감은
  /// (이미 활성 상태이므로) 서버가 본문을 덮어쓰지 않고 그대로 재사용하지만
  /// 이 세션은 그 사실을 모른 채 여전히 `local://` placeholder가 남은
  /// 로컬 본문으로 첨부를 시도해 "이 세션이 만들지 않은 활성 기존
  /// 독후감에 첨부 시도"(400)로 다시 실패할 수 있다. 이 잔여 위험을
  /// 닫으려면 청크·완료 결과를 내구성 있게 남겨 세션 간에 이어 받는
  /// 별도의 복구 저장소가 필요한데, 이는 "세션을 이어서 복구하지 않는다"는
  /// 이 기능의 명시적 범위를 벗어난다(§ 금지 사항) — 실제로 이미지가 있는
  /// 독후감에서 이 경로로 반복 실패하면, 그 독후감을 수정(제목·내용을
  /// 살짝 바꿔 `content_json`에서 placeholder를 없애는 등)해 다음 재시도가
  /// 첨부를 시도하지 않게 하거나 서버 쪽에서 정리해야 한다.
  @override
  Future<void> applyResults(RecordImportAppliedResults results) async {
    final db = await BookshelfDatabase.instance();
    await db.transaction((txn) async {
      await bookshelfDao.applyImportResults(txn, results.bookServerIdByLocalId);
      await noteDao.applyImportResults(
        txn,
        noteServerIdByLocalId: results.noteServerIdByLocalId,
        memoServerIdByLocalId: results.memoServerIdByLocalId,
        memoImageUrlByLocalId: results.memoImageUrlByLocalId,
      );
      await reflectionDao.applyImportResults(
        txn,
        resultsByLocalId: results.reflectionResultsByLocalId,
      );
      await tagDao.applyImportResults(
        txn,
        tagServerIdByLocalId: results.tagServerIdByLocalId,
        mappingServerIdByLocalId: results.tagMapServerIdByLocalId,
      );
    });
  }

  @override
  Future<void> switchToServerMode() => storageMode.resetToServer();
}
