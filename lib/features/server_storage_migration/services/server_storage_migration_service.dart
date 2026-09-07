import 'dart:developer' as developer;
import 'dart:io';

import '../../book_reflection/data/book_reflection_dao.dart';
import '../../book_reflection/services/book_reflection_content_adapter.dart';
import '../data/record_import_payload_builder.dart';
import '../data/server_storage_migration_steps.dart';

enum ServerStorageMigrationStage {
  /// 아직 시작하지 않음.
  idle,

  /// 로컬 DB를 훑어 보낼 데이터를 준비하는 중(§ 요구사항 8 "기록 준비").
  preparing,

  /// 책·노트·메모·독후감·태그를 청크로 업로드하는 중(§ "기록 업로드").
  uploadingRecords,

  /// 메모 사진·독후감 이미지를 업로드하는 중(§ "이미지 업로드").
  uploadingImages,

  /// `/complete` 호출과 로컬 DB 확정 반영 중(§ "완료 처리").
  completing,

  completed,
  failed,
}

class ServerStorageMigrationState {
  const ServerStorageMigrationState({
    this.stage = ServerStorageMigrationStage.idle,
    this.recordsDone = 0,
    this.recordsTotal = 0,
    this.imagesDone = 0,
    this.imagesTotal = 0,
    this.failureMessage,
  });

  final ServerStorageMigrationStage stage;

  /// 업로드한/전체 청크 수.
  final int recordsDone;
  final int recordsTotal;
  final int imagesDone;
  final int imagesTotal;
  final String? failureMessage;

  bool get isRunning =>
      stage != ServerStorageMigrationStage.idle &&
      stage != ServerStorageMigrationStage.completed &&
      stage != ServerStorageMigrationStage.failed;

  double? get recordProgress =>
      recordsTotal == 0 ? null : recordsDone / recordsTotal;

  double? get imageProgress =>
      imagesTotal == 0 ? null : imagesDone / imagesTotal;

  ServerStorageMigrationState copyWith({
    ServerStorageMigrationStage? stage,
    int? recordsDone,
    int? recordsTotal,
    int? imagesDone,
    int? imagesTotal,
    String? failureMessage,
  }) {
    return ServerStorageMigrationState(
      stage: stage ?? this.stage,
      recordsDone: recordsDone ?? this.recordsDone,
      recordsTotal: recordsTotal ?? this.recordsTotal,
      imagesDone: imagesDone ?? this.imagesDone,
      imagesTotal: imagesTotal ?? this.imagesTotal,
      failureMessage: failureMessage,
    );
  }
}

/// 로컬 저장 → 서버 저장 모드 재전환을 순서대로 실행한다.
///
/// 1. 기록 준비(로컬 스냅샷 + 사전 검증) → 2. `/start` → 3. `/items` 청크
/// 업로드 → 4. `/attachments` 이미지 업로드 → 5. `/complete` → 6. 로컬 DB
/// 확정 반영 + 저장 모드 전환.
///
/// **로컬 DB 반영은 5가 성공한 뒤에만** 한다(6을 5보다 먼저 하지 않는다) —
/// 3·4·5 중 어디서든 실패하면 서버가 이 세션이 만든 데이터를 전부 정리하고
/// 세션을 지운다(문서 "실패 시 동작"). 청크 응답을 받는 즉시 로컬에
/// server_id를 기록해 버리면, 그 뒤 단계가 실패했을 때 로컬에는 더 이상
/// 서버에 존재하지 않는 행의 ID가 남아 다음 전체 동기화가 "서버에서 사라진
/// 정상 행"으로 오인해 로컬 원본까지 지워버릴 수 있다(§ 요구사항 7 로컬
/// 데이터 보존과 정면으로 충돌).
///
/// 이 서비스는 실패해도 [ServerStorageMigrationSteps.startSession] 이후의
/// 실패에 대해 별도로 취소(`cancel`)를 호출하지 않는다 — items/attachments/
/// complete 실패는 문서상 서버가 이미 세션 전체를 정리하므로, 추가 취소는
/// 불필요한 404/409만 만든다. 재시도는 항상 `/start`부터 완전히 새로
/// 시작한다(§ 요구사항 1, 6).
class ServerStorageMigrationService {
  ServerStorageMigrationService(this._steps);

  final ServerStorageMigrationSteps _steps;

  static const _contentAdapter = BookReflectionContentAdapter();

  Future<ServerStorageMigrationState> run({
    void Function(ServerStorageMigrationState state)? onProgress,
  }) async {
    var state = const ServerStorageMigrationState(
      stage: ServerStorageMigrationStage.preparing,
    );
    void emit(ServerStorageMigrationState next) {
      state = next;
      onProgress?.call(next);
    }

    emit(state);
    try {
      if (!await _steps.ensureNoPendingServerCleanup()) {
        return _failed(
          emit,
          state,
          '이전 전환에서 남은 서버 기록 정리가 끝나지 않았습니다. 잠시 후 다시 시도해 주세요.',
        );
      }

      final outcome = await _steps.prepare();
      if (!outcome.isSuccess) {
        developer.log('[서버 저장 전환] result=FAIL reason=preflight');
        return _failed(emit, state, outcome.failureMessage!);
      }
      final snapshot = outcome.snapshot!;

      final session = await _steps.startSession();
      final chunks = buildRecordImportChunks(
        books: snapshot.books.map(bookToImportJson).toList(),
        tags: snapshot.tags.map(tagToImportJson).toList(),
        notes: snapshot.notes.map(noteToImportJson).toList(),
        noteMemos: snapshot.noteMemos.map(noteMemoToImportJson).toList(),
        reflections: snapshot.reflections.map(reflectionToImportJson).toList(),
        tagMaps: snapshot.tagMaps.map(tagMapToImportJson).toList(),
        maxChunkItemCount: session.maxChunkItemCount,
      );

      emit(
        state.copyWith(
          stage: ServerStorageMigrationStage.uploadingRecords,
          recordsTotal: chunks.length,
        ),
      );
      final bookServerIds = <int, int>{};
      final noteServerIds = <int, int>{};
      final memoServerIds = <int, int>{};
      final reflectionServerIds = <int, int>{};
      final tagServerIds = <int, int>{};
      final tagMapServerIds = <int, int>{};
      // `created: true`인 PHOTO 메모는 완전히 새 행이라 사진이 전혀
      // 연결돼 있지 않다 — `RecordImportSnapshot.fallbackMemoImages`에
      // 예비로 들고 있던 파일을 실제로 올려야 하는지 판단하는 데 쓴다.
      final createdMemoLocalIds = <int>{};
      for (var i = 0; i < chunks.length; i++) {
        final result = await _steps.uploadChunk(session.importId, chunks[i]);
        for (final r in result.books) {
          bookServerIds[r.localId] = r.serverId;
        }
        for (final r in result.notes) {
          noteServerIds[r.localId] = r.serverId;
        }
        for (final r in result.noteMemos) {
          memoServerIds[r.localId] = r.serverId;
          if (r.created) createdMemoLocalIds.add(r.localId);
        }
        for (final r in result.reflections) {
          reflectionServerIds[r.localId] = r.serverId;
        }
        for (final r in result.tags) {
          tagServerIds[r.localId] = r.serverId;
        }
        for (final r in result.tagMaps) {
          tagMapServerIds[r.localId] = r.serverId;
        }
        emit(
          state.copyWith(
            stage: ServerStorageMigrationStage.uploadingRecords,
            recordsDone: i + 1,
            recordsTotal: chunks.length,
          ),
        );
      }

      final reflectionsById = {
        for (final r in snapshot.reflections) r.reflection.id: r,
      };
      // 항상 올려야 하는 메모 + "알고 보니 새 행이라" 예비 파일을 실제로
      // 올려야 하는 메모를 합친다.
      final memoImagesToUpload = <int, File>{
        ...snapshot.pendingMemoImages,
        for (final entry in snapshot.fallbackMemoImages.entries)
          if (createdMemoLocalIds.contains(entry.key)) entry.key: entry.value,
      };
      final totalImages =
          memoImagesToUpload.length +
          snapshot.pendingReflectionImages.values.fold<int>(
            0,
            (sum, list) => sum + list.length,
          );
      emit(
        state.copyWith(
          stage: ServerStorageMigrationStage.uploadingImages,
          imagesDone: 0,
          imagesTotal: totalImages,
        ),
      );
      var imagesDone = 0;
      final memoImageUrls = <int, String>{};
      for (final entry in memoImagesToUpload.entries) {
        // 청크 응답에 없으면(이론상 없어야 함) 올릴 서버 메모가 없다는
        // 뜻이라 건너뛴다 — 남은 placeholder는 `/complete`의 이미지 연결
        // 검증이 대신 잡아 세션 전체를 실패시킨다.
        if (!memoServerIds.containsKey(entry.key)) continue;
        final attachment = await _steps.uploadMemoImage(
          session.importId,
          entry.key,
          entry.value,
        );
        memoImageUrls[entry.key] = attachment.imageUrl;
        imagesDone++;
        emit(state.copyWith(imagesDone: imagesDone, imagesTotal: totalImages));
      }

      final reflectionUploadedImages =
          <int, List<({String remoteUrl, String localImagePath})>>{};
      final reflectionFinalContent = <int, Map<String, dynamic>>{};
      for (final entry in snapshot.pendingReflectionImages.entries) {
        final reflectionLocalId = entry.key;
        if (!reflectionServerIds.containsKey(reflectionLocalId)) continue;
        final replacements = <String, String>{};
        final uploaded = <({String remoteUrl, String localImagePath})>[];
        for (final placeholder in entry.value) {
          final attachment = await _steps.uploadReflectionImage(
            session.importId,
            reflectionLocalId,
            placeholder.placeholder,
            placeholder.file,
          );
          replacements[placeholder.placeholder] = attachment.imageUrl;
          uploaded.add((
            remoteUrl: attachment.imageUrl,
            localImagePath: placeholder.localImagePath,
          ));
          imagesDone++;
          emit(
            state.copyWith(imagesDone: imagesDone, imagesTotal: totalImages),
          );
        }
        reflectionUploadedImages[reflectionLocalId] = uploaded;
        final original = reflectionsById[reflectionLocalId]!
            .contentJsonForImport;
        reflectionFinalContent[reflectionLocalId] = _contentAdapter
            .replaceImageSources(original, replacements);
      }

      emit(state.copyWith(stage: ServerStorageMigrationStage.completing));
      await _steps.complete(session.importId, snapshot.counts);

      final reflectionResults = <int, ReflectionImportResult>{
        for (final entry in reflectionServerIds.entries)
          entry.key: (
            serverId: entry.value,
            finalContentJson: reflectionFinalContent[entry.key],
            uploadedImages: reflectionUploadedImages[entry.key] ?? const [],
          ),
      };

      // 여기서부터는 서버 Import가 이미 확정(COMPLETED)됐다 — 아래가 실패해도
      // 서버 데이터는 안전하며, 다음 재시도도 멱등 키 덕분에 중복 생성 없이
      // 안전하다(이 구현은 그 희귀 케이스를 위해 별도 복구 경로를 두지
      // 않고, 다른 실패와 동일하게 다시 시도하도록 안내한다).
      await _steps.applyResults(
        RecordImportAppliedResults(
          bookServerIdByLocalId: bookServerIds,
          noteServerIdByLocalId: noteServerIds,
          memoServerIdByLocalId: memoServerIds,
          memoImageUrlByLocalId: memoImageUrls,
          reflectionResultsByLocalId: reflectionResults,
          tagServerIdByLocalId: tagServerIds,
          tagMapServerIdByLocalId: tagMapServerIds,
        ),
      );
      await _steps.switchToServerMode();

      emit(state.copyWith(stage: ServerStorageMigrationStage.completed));
      developer.log('[서버 저장 전환] result=SUCCESS');
      return state;
    } catch (error) {
      developer.log('[서버 저장 전환] result=FAIL reason=${error.runtimeType}');
      return _failed(emit, state, '가져오기에 실패했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  ServerStorageMigrationState _failed(
    void Function(ServerStorageMigrationState) emit,
    ServerStorageMigrationState state,
    String message,
  ) {
    final failed = state.copyWith(
      stage: ServerStorageMigrationStage.failed,
      failureMessage: message,
    );
    emit(failed);
    return failed;
  }
}
