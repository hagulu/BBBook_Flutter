import 'dart:developer' as developer;

import '../../../core/network/api_exception.dart';
import '../../../core/storage/local_image_store.dart';
import '../../book_note/data/book_note_repository.dart';
import '../../book_reflection/data/book_reflection_repository.dart';
import '../../bookshelf/data/bookshelf_database.dart';
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
  Future<String?> applyLatestRecords() async {
    // 저장소별 동기화는 각자 다른 시점의 서버 상태를 받으므로, 서버 정리에
    // 보낼 exportedAt은 네 테이블에 **같은 한 번의 응답**을 반영해야만
    // "이 시각까지의 서버 기록이 로컬에 있다"를 뜻한다. 진행 중인 동기화가
    // 이 응답보다 오래된 결과를 뒤늦게 덮어쓰지 않도록 먼저 기다린다.
    await _waitForCurrentSyncs();
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final requestedAt = DateTime.now().toUtc();
    final payload = await recordSyncApi.getAllRecords();
    final baseline = payload.exportedAtTime ?? requestedAt;
    // 책장부터 맞춰야 노트/독후감/태그가 붙을 로컬 책 행이 존재한다.
    final applied =
        await bookshelfRepository.applyFullRecords(
          payload.books,
          expectedGeneration: expectedGeneration,
          baseline: baseline,
        ) &&
        await noteRepository.applyFullRecords(
          payload,
          ownerUserId: ownerUserId,
          expectedGeneration: expectedGeneration,
          baseline: baseline,
        ) &&
        await reflectionRepository.applyFullRecords(
          payload,
          ownerUserId: ownerUserId,
          expectedGeneration: expectedGeneration,
          baseline: baseline,
        ) &&
        await tagRepository.applyFullRecords(
          payload,
          expectedGeneration: expectedGeneration,
          baseline: baseline,
        );
    if (!applied) {
      // 그 사이 로그아웃 등으로 로컬 DB가 바뀌었다. 반영하지 못한 응답의
      // exportedAt으로 서버를 정리하면 안 된다.
      throw StateError('Session changed while applying records');
    }
    developer.log(
      '[로컬 저장 이전 기록 반영] userId=$ownerUserId '
      'count=${payload.totalItemCount} '
      'exportedAt=${payload.exportedAt ?? "none"} result=SUCCESS',
    );
    return payload.exportedAt;
  }

  Future<void> _waitForCurrentSyncs() => Future.wait([
    bookshelfRepository.waitForCurrentSync(),
    noteRepository.waitForCurrentSync(),
    reflectionRepository.waitForCurrentSync(),
    tagRepository.waitForCurrentSync(),
  ]);

  @override
  Future<LocalImageSyncReport> downloadAllImages(
    void Function(int done, int total) onProgress,
  ) async {
    // 다운로드 대상과 누락 수는 DB 연결 유무로 판정한다. 동기화가 기다리지
    // 않고 넘긴 정리(파일이 사라진 연결 끊기)가 끝나기 전에 세면, 파일 없는
    // 이미지를 이미 확보한 것으로 보고 서버 정리까지 진행할 수 있다.
    await Future.wait([
      noteRepository.sweepLocalImages(),
      reflectionRepository.sweepLocalImages(),
    ]);

    // 메모 사진·독후감 이미지·직접 올린 책 표지의 진행률을 하나로 합쳐
    // 보여준다.
    var memoDone = 0;
    var memoTotal = 0;
    var reflectionDone = 0;
    var reflectionTotal = 0;
    var coverDone = 0;
    var coverTotal = 0;
    void emit() => onProgress(
      memoDone + reflectionDone + coverDone,
      memoTotal + reflectionTotal + coverTotal,
    );

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
    final coverReport = await bookshelfRepository.downloadUploadedCovers(
      onProgress: (done, total) {
        coverDone = done;
        coverTotal = total;
        emit();
      },
    );
    return memoReport + reflectionReport + coverReport;
  }

  @override
  Future<int> countMissingLocalImages() async {
    return await noteRepository.countImagesPendingDownload() +
        await reflectionRepository.countImagesPendingDownload() +
        await bookshelfRepository.countUploadedCoversPendingDownload();
  }

  @override
  Future<void> switchToLocalMode({required String? exportedAt}) async {
    await storageMode.switchToLocal(
      ownerUserId: ownerUserId,
      exportedAt: exportedAt,
    );
    // 새 동기화는 로컬 모드 게이트에서 차단된다. 이미 시작한 응답 적용이
    // 끝나기 전에는 서버를 삭제하지 않는다.
    await _waitForCurrentSyncs();
    // 동기화가 멈춘 뒤에 바꿔야 서버 응답이 표지를 서버 URL로 되돌리지 않는다.
    await bookshelfRepository.promoteLocalCoverCopies();
  }

  @override
  Future<void> updateExportedAt(String? exportedAt) =>
      storageMode.updateServerDeleteExportedAt(exportedAt);

  @override
  Future<String?> pendingExportedAt() => storageMode.serverDeleteExportedAt();

  @override
  Future<void> deleteServerRecords({required String? exportedAt}) async {
    // 바뀐 기록 때문에 거절된 뒤 [applyLatestRecords]로 다시 반영하면 책
    // 표지가 서버 URL로 되돌아간다. 서버를 지우면 그 URL도 사라지므로,
    // 삭제 직전마다 다시 승격한다(이미 승격된 행은 조건에 걸리지 않는다).
    await bookshelfRepository.promoteLocalCoverCopies();
    try {
      await recordSyncApi.deleteAllRecords(exportedAt: exportedAt);
    } on ApiException catch (error) {
      if (RecordSyncApi.isRecordsChangedSinceExport(error)) {
        throw const ServerRecordsChangedException();
      }
      rethrow;
    }
  }

  @override
  Future<void> markServerRecordsDeleted() =>
      storageMode.markServerRecordsDeleted();
}
