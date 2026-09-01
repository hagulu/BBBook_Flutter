import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/local_image_store.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../bookshelf/data/bookshelf_repository.dart';
import '../../record_sync/data/record_sync_api.dart';
import '../models/book_reflection.dart';
import '../services/book_reflection_content_adapter.dart';
import '../services/reflection_image_mapping.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import '../services/reflection_image_store.dart';
import 'book_reflection_api.dart';
import 'book_reflection_dao.dart';

/// 독후감 화면의 source of truth.
///
/// 화면은 항상 이 Repository를 통해 로컬 DB를 읽고 쓴다. 작성/수정은 로컬에
/// 즉시 반영한 뒤 dirty push하고, 실패한 행은 다음 [sync]에서 재시도한다.
///
/// 본문 이미지도 같은 원칙을 따른다. 편집 중 추가한 이미지는 업로드 없이
/// [saveLocalImage]로 먼저 로컬에 저장해 본문에 로컬 경로로 들어가고,
/// 서버로 push할 때 비로소 업로드해 그 URL로 바꾼 본문을 보낸다. 업로드한
/// 사본과 서버 URL의 짝은 로컬 전용 테이블(`reflection_image_local`)에
/// 남겨, 이후 조회/편집은 서버에서 다시 받지 않고 로컬 파일을 쓴다. 서버
/// 이미지는 그 독후감을 실제로 열 때([ensureImagesForReflection]) 받는다.
class BookReflectionRepository {
  BookReflectionRepository({
    required this._api,
    required this._recordSyncApi,
    required this._bookshelfRepository,
    this._dao = const BookReflectionDao(),
    LocalImageStore? imageStore,
    StorageModeStore? storageMode,
  }) : _imageStore = imageStore ?? reflectionImageStore,
       _storageMode = storageMode ?? storageModeStore;

  static const _adapter = BookReflectionContentAdapter();

  /// 이 횟수만큼 연달아 일시적 실패가 나면 네트워크가 끊긴 것으로 보고
  /// 이번 회차를 접는다.
  static const _maxConsecutiveDownloadFailures = 3;

  /// 세션 동안 기억할 "서버에 없는 이미지" URL 상한.
  static const _maxUnavailableImageUrls = 200;

  final BookReflectionApi _api;
  final RecordSyncApi _recordSyncApi;
  final BookshelfRepository _bookshelfRepository;
  final BookReflectionDao _dao;
  final LocalImageStore _imageStore;
  final StorageModeStore _storageMode;
  final Map<int, Future<void>> _dirtyPushChains = {};

  Future<void>? _sweepInFlight;
  final Set<String> _unavailableImageUrls = {};
  int? _unavailableSessionGeneration;

  Future<List<BookReflection>> findByUserBook({
    required int ownerUserId,
    required int userBookId,
  }) {
    return _dao.findByUserBook(
      ownerUserId: ownerUserId,
      userBookId: userBookId,
    );
  }

  Future<BookReflection?> findDetail({
    required int ownerUserId,
    required int userBookId,
    required int reflectionId,
  }) {
    return _dao.findDetail(
      ownerUserId: ownerUserId,
      userBookId: userBookId,
      reflectionId: reflectionId,
    );
  }

  /// 서버 PK로 로컬 행을 찾는다. "내가 작성한 독후감" 목록처럼 서버
  /// reflectionId만 아는 화면이 기존 로컬 우선 상세/수정/삭제 화면
  /// ([findDetail] 기준, 로컬 PK 필요)으로 연결할 때 사용한다.
  Future<BookReflection?> findByServerId({
    required int ownerUserId,
    required int serverId,
  }) {
    return _dao.getByServerId(ownerUserId: ownerUserId, serverId: serverId);
  }

  Future<BookReflection> save({
    required int ownerUserId,
    required int userBookId,
    required int? reflectionId,
    required BookReflectionDraft draft,
  }) async {
    final operation = reflectionId == null ? '독후감 생성' : '독후감 수정';
    try {
      final reflection = reflectionId == null
          ? await _dao.createLocal(
              ownerUserId: ownerUserId,
              userBookId: userBookId,
              draft: draft,
            )
          : await _dao.updateLocal(
              ownerUserId: ownerUserId,
              userBookId: userBookId,
              reflectionId: reflectionId,
              draft: draft,
            );
      developer.log(
        '[$operation] userId=$ownerUserId bookId=$userBookId '
        'reflectionId=${reflection.id} result=SUCCESS',
      );
      unawaited(pushReflection(reflection.id));
      return reflection;
    } catch (_) {
      developer.log(
        '[$operation] userId=$ownerUserId bookId=$userBookId '
        'reflectionId=${reflectionId ?? 'new'} '
        'result=FAIL reason=local_storage_error',
      );
      rethrow;
    }
  }

  Future<BookReflection> setPublic({
    required int ownerUserId,
    required int userBookId,
    required int reflectionId,
    required bool isPublic,
  }) async {
    try {
      final current = await _dao.getByLocalId(reflectionId);
      if (current == null || current.deletedAt != null) {
        throw StateError('Reflection not found');
      }
      // 로컬 저장 모드에서는 서버에 이 독후감이 남아 있지 않다 — 공개
      // 설정은 로컬 값만 바꾼다(서버 호출은 404가 될 뿐이고, 기록을 서버로
      // 올리지 않는다는 정책에도 어긋난다).
      if (current.serverId != null && !await _storageMode.isLocal()) {
        await _api.updateVisibility(
          reflectionId: current.serverId!,
          isPublic: isPublic,
        );
      }
      final reflection = await _dao.updateVisibilityLocal(
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        reflectionId: reflectionId,
        isPublic: isPublic,
      );
      developer.log(
        '[독후감 공개 설정] userId=$ownerUserId bookId=$userBookId '
        'reflectionId=$reflectionId result=SUCCESS',
      );
      return reflection;
    } catch (error) {
      developer.log(
        '[독후감 공개 설정] userId=$ownerUserId bookId=$userBookId '
        'reflectionId=$reflectionId result=FAIL reason=${_reasonOf(error)}',
      );
      rethrow;
    }
  }

  Future<void> delete({
    required int ownerUserId,
    required int userBookId,
    required int reflectionId,
  }) async {
    try {
      final reflection = await _dao.markDeletedLocal(
        ownerUserId: ownerUserId,
        userBookId: userBookId,
        reflectionId: reflectionId,
      );
      // 로컬 저장 모드에서는 서버에 알릴 삭제가 없으므로 soft delete 행을
      // 바로 정리한다(이미지 파일은 정리 스윕이 지운다).
      if (await _storageMode.isLocal()) {
        await _dao.confirmDelete(
          localId: reflection.id,
          capturedUpdatedAt: reflection.updatedAt,
        );
        await _dao.deleteLocalImagesFor(reflection.id);
      }
      developer.log(
        '[독후감 삭제] userId=$ownerUserId bookId=$userBookId '
        'reflectionId=$reflectionId result=SUCCESS',
      );
      unawaited(pushReflection(reflection.id));
    } catch (error) {
      developer.log(
        '[독후감 삭제] userId=$ownerUserId bookId=$userBookId '
        'reflectionId=$reflectionId result=FAIL reason=${_reasonOf(error)}',
      );
      rethrow;
    }
  }

  /// 편집기에서 고른 이미지를 로컬 저장소로 복사하고 본문에 넣을 상대
  /// 경로를 반환한다. 서버 업로드는 하지 않는다 — 오프라인에서도 이미지를
  /// 넣어 작성/수정할 수 있어야 하므로, 업로드는 push 시점으로 미룬다
  /// ([_uploadPendingImages]).
  Future<String> saveLocalImage(String filePath) async {
    try {
      final localImagePath = await _imageStore.saveSelected(filePath);
      developer.log('[독후감 이미지 로컬 저장] result=SUCCESS');
      return localImagePath;
    } on FileSystemException catch (error) {
      developer.log('[독후감 이미지 로컬 저장] result=FAIL reason=invalid_image');
      // 형식/용량 위반 메시지는 그대로 사용자에게 보여준다.
      throw ApiException(
        error.message.isEmpty ? '선택한 이미지를 찾을 수 없습니다.' : error.message,
      );
    } catch (error) {
      developer.log('[독후감 이미지 로컬 저장] result=FAIL reason=local_file_error');
      throw const ApiException('이미지를 저장하지 못했습니다.');
    }
  }

  /// 본문의 서버 이미지 URL을 로컬 사본 경로로 바꿔 주는 매칭. 화면은 이
  /// 값으로 이미지를 로컬 파일에서 먼저 읽는다(없으면 서버 URL로 대체).
  Future<Map<String, String>> findLocalImagePaths(int reflectionId) =>
      _dao.findLocalImagePaths(reflectionId);

  // ---------------------------------------------------------------------
  // 서버 동기화
  // ---------------------------------------------------------------------

  Future<DateTime?> getLastSyncedAtReflection() =>
      _dao.getLastSyncedAtReflection();

  /// since가 없으면 전체 동기화, 있으면 증분 동기화 → 증분 응답이
  /// fullSyncRequired면 전체 동기화로 대체. [BookNoteRepository.sync]와
  /// 같은 구조다.
  ///
  /// 반환값은 실제로 로컬 DB가 바뀌었는지 여부.
  Future<bool> sync({required int ownerUserId}) async {
    // 로컬 저장 모드에서는 서버와 주고받지 않는다(로컬 파일 정리만 계속한다).
    if (await _storageMode.isLocal()) {
      unawaited(sweepLocalImages());
      return false;
    }
    final expectedGeneration = BookshelfDatabase.sessionGeneration;

    await pushAllDirty();
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }

    final since = await _dao.getLastSyncedAtReflection();
    if (since == null) {
      final changed = await _fullSync(ownerUserId, expectedGeneration);
      unawaited(sweepLocalImages());
      return changed;
    }

    final result = await _api.getSyncChanges(since: since);
    if (result.fullSyncRequired) {
      // 증분 응답의 syncedAt(서버 시각)을 기준값으로 쓴다 — 클라이언트
      // now()를 쓰면 기기 시계가 서버보다 앞서 있을 때 그 오차만큼 이후
      // 서버 변경을 영구히 놓칠 수 있다.
      final changed = await _fullSync(
        ownerUserId,
        expectedGeneration,
        baseline: result.syncedAt,
      );
      unawaited(sweepLocalImages());
      return changed;
    }
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }

    await _dao.applyReflectionChanges(
      ownerUserId: ownerUserId,
      upsertedReflections: result.upsertedReflections,
      deletedReflectionIds: result.deletedReflectionIds,
      syncedAt: result.syncedAt,
    );
    unawaited(sweepLocalImages());
    return result.upsertedReflections.isNotEmpty ||
        result.deletedReflectionIds.isNotEmpty;
  }

  /// [baseline]을 넘기지 않으면(최초 동기화 등 서버 시각을 알 수 없을 때)
  /// 요청 직전 클라이언트 시각(UTC)을 기준값으로 쓴다. `/api/me/records`(최초
  /// 기록 전체 조회 — record_sync 기능과 같은 API)를 그대로 재사용한다.
  Future<bool> _fullSync(
    int ownerUserId,
    int expectedGeneration, {
    DateTime? baseline,
  }) async {
    final requestedAt = baseline ?? DateTime.now().toUtc();
    final payload = await _recordSyncApi.getAllRecords();
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }
    await _dao.reconcileFullReflection(
      ownerUserId: ownerUserId,
      activeUserBookIds: payload.books
          .map((b) => b.userBookId)
          .toList(growable: false),
      reflections: payload.reflections,
      requestedAt: requestedAt,
    );
    return true;
  }

  Future<void> pushAllDirty() async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    for (final reflection in await _dao.getDirty()) {
      if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
      await pushReflection(reflection.id);
    }
  }

  Future<void> pushReflection(int localReflectionId) {
    final previous =
        _dirtyPushChains[localReflectionId] ?? Future<void>.value();
    final chained = previous
        .then((_) => _pushOne(localReflectionId))
        .catchError((_, _) {});
    _dirtyPushChains[localReflectionId] = chained;
    return chained;
  }

  Future<void> _pushOne(int localReflectionId) async {
    if (await _storageMode.isLocal()) return;
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final reflection = await _dao.getByLocalId(localReflectionId);
    if (reflection == null || !reflection.isDirty) return;
    if (reflection.deletedAt != null) {
      try {
        if (reflection.serverId != null) {
          await _api.delete(reflection.serverId!);
        }
        if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
        await _dao.confirmDelete(
          localId: localReflectionId,
          capturedUpdatedAt: reflection.updatedAt,
        );
        await _dao.deleteLocalImagesFor(localReflectionId);
        developer.log(
          '[독후감 삭제 push] reflectionId=$localReflectionId result=SUCCESS',
        );
      } on ApiException catch (error) {
        if (error.statusCode == 404) {
          if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
          await _dao.confirmDelete(
            localId: localReflectionId,
            capturedUpdatedAt: reflection.updatedAt,
          );
          await _dao.deleteLocalImagesFor(localReflectionId);
          developer.log(
            '[독후감 삭제 push] reflectionId=$localReflectionId '
            'result=SUCCESS reason=already_deleted',
          );
          return;
        }
        developer.log(
          '[독후감 삭제 push] reflectionId=$localReflectionId '
          'result=FAIL reason=${_reasonOf(error)}',
        );
      } catch (error) {
        developer.log(
          '[독후감 삭제 push] reflectionId=$localReflectionId '
          'result=FAIL reason=${_reasonOf(error)}',
        );
      }
      return;
    }
    final book = await _bookshelfRepository.getById(reflection.userBookId);
    final serverUserBookId = book?.serverId;
    if (serverUserBookId == null) {
      developer.log(
        '[독후감 더티 push] reflectionId=$localReflectionId '
        'result=FAIL reason=book_create_pending',
      );
      return;
    }
    final title = reflection.title;
    final contentJson = reflection.contentJson;
    final contentText = reflection.contentText;
    if (title == null || contentJson == null || contentText == null) return;

    final documentSources = _adapter.imageSources(contentJson);
    final _ImageUploadResult upload;
    try {
      upload = await _uploadPendingImages(localReflectionId, documentSources);
    } catch (error) {
      developer.log(
        '[독후감 더티 push] reflectionId=$localReflectionId '
        'result=FAIL reason=${_reasonOf(error)}',
      );
      // 이미지를 못 올린 채 본문만 보내면 서버에 로컬 경로가 저장된다 —
      // dirty를 유지해 다음 동기화에서 통째로 다시 시도한다.
      return;
    }
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;

    final draft = BookReflectionDraft(
      title: title,
      contentJson: _adapter.replaceImageSources(
        contentJson,
        upload.uploadedUrlBySource,
      ),
      contentText: contentText,
      isPublic: reflection.isPublic,
    );
    try {
      final result = reflection.serverId == null
          ? await _api.create(
              userBookId: serverUserBookId,
              draft: draft,
              clientRequestId: reflection.clientRequestId,
            )
          : await _api.update(reflectionId: reflection.serverId!, draft: draft);
      if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
      final applied = await _dao.confirmPush(
        localId: localReflectionId,
        capturedUpdatedAt: reflection.updatedAt,
        result: result,
      );
      // 로컬 본문이 서버 응답으로 갱신됐을 때만 매칭을 남긴다. 그렇지 않으면
      // (push 중 사용자가 또 편집) 로컬 본문은 여전히 로컬 경로를 들고 있어,
      // 응답 URL로 매칭을 만들어도 본문 어디에서도 쓰이지 않는다.
      if (applied) {
        await _dao.replaceLocalImages(
          reflectionId: localReflectionId,
          mappings: resolveReflectionImageMappings(
            documentSources: documentSources,
            responseSources: _adapter.imageSources(result.contentJson),
            localImagePathBySource: upload.localImagePathBySource,
          ),
        );
      }
      developer.log(
        '[독후감 더티 push] reflectionId=$localReflectionId result=SUCCESS',
      );
    } catch (error) {
      developer.log(
        '[독후감 더티 push] reflectionId=$localReflectionId '
        'result=FAIL reason=${_reasonOf(error)}',
      );
    }
  }

  /// 본문에 남아 있는 "아직 서버에 없는" 로컬 이미지를 업로드한다.
  ///
  /// 반환값의 [_ImageUploadResult.uploadedUrlBySource]로 본문의 로컬 경로를
  /// 서버 URL로 치환하고, [_ImageUploadResult.localImagePathBySource]는
  /// push 응답과 짝지어 매칭을 갱신하는 데 쓴다(이미 서버에 올라가 있던
  /// 이미지의 기존 매칭도 함께 담아, 서버가 URL을 바꿔 돌려줘도 로컬
  /// 사본을 계속 이어 쓸 수 있게 한다).
  Future<_ImageUploadResult> _uploadPendingImages(
    int localReflectionId,
    List<String> documentSources,
  ) async {
    final existing = await _dao.findLocalImagePaths(localReflectionId);
    final uploadedUrlBySource = <String, String>{};
    final localImagePathBySource = <String, String>{};
    for (final source in documentSources.toSet()) {
      if (LocalImageStore.isRemote(source)) {
        final localImagePath = existing[source];
        if (localImagePath != null) {
          localImagePathBySource[source] = localImagePath;
        }
        continue;
      }
      final file = await _imageStore.resolve(source);
      if (file == null || !await file.exists()) {
        // 본문은 있는데 파일이 사라졌다. 로컬 경로를 그대로 서버에 저장하면
        // 어느 기기에서도 못 여는 이미지가 되므로 push 자체를 미룬다.
        throw const ApiException('본문 이미지 파일을 찾을 수 없습니다.');
      }
      uploadedUrlBySource[source] = await _api.uploadTempImage(file);
      localImagePathBySource[source] = source;
    }
    if (uploadedUrlBySource.isNotEmpty) {
      developer.log(
        '[독후감 이미지 업로드] reflectionId=$localReflectionId '
        'count=${uploadedUrlBySource.length} result=SUCCESS',
      );
    }
    return _ImageUploadResult(
      uploadedUrlBySource: uploadedUrlBySource,
      localImagePathBySource: localImagePathBySource,
    );
  }

  String _reasonOf(Object error) {
    if (error is ApiException) {
      return switch (error.statusCode) {
        400 => 'validation_failed',
        401 => 'unauthorized',
        404 => 'not_found',
        _ => 'network_or_server_error',
      };
    }
    return 'unexpected_error';
  }

  // ---------------------------------------------------------------------
  // 본문 이미지 로컬 사본 관리
  // ---------------------------------------------------------------------

  /// 한 독후감의 서버 본문 이미지를 **필요한 시점에** 로컬로 내려받는다
  /// (상세·편집 화면 진입 등).
  ///
  /// 최초 로그인 전체 동기화에서 모든 이미지를 미리 받지 않는 이유는 기록이
  /// 많은 사용자의 첫 진입이 그만큼 느려지기 때문이다. 한 번 받은 이미지는
  /// 매칭이 남아 계속 로컬 파일을 쓴다.
  ///
  /// 반환값은 실제로 새로 받은 이미지가 있었는지 여부(화면 갱신 판단용).
  Future<bool> ensureImagesForReflection(int reflectionId) async {
    if (await _storageMode.isLocal()) return false;
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    _resetUnavailableIfSessionChanged(expectedGeneration);
    final reflection = await _dao.getByLocalId(reflectionId);
    if (reflection == null || reflection.deletedAt != null) return false;
    final report = await _downloadImagesFor(
      reflectionId,
      _adapter.imageSources(reflection.contentJson),
      expectedGeneration,
    );
    return report.stored > 0;
  }

  /// 서버에 있는 모든 독후감 본문 이미지를 로컬로 내려받는다. 로컬 저장
  /// 모드 전환 이전([LocalStorageMigrationService]) 전용 경로다.
  Future<LocalImageSyncReport> downloadAllImages({
    void Function(int done, int total)? onProgress,
  }) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    _resetUnavailableIfSessionChanged(expectedGeneration);
    // 진행률의 분모와 분자를 같은 기준으로 맞추기 위해, 실제로 받아야 할
    // 이미지를 먼저 모두 추려 전체 개수를 확정한다(이미 로컬에 있는
    // 이미지를 분모에 넣으면 진행률이 100%에 닿지 못한다).
    final pendingByReflection = <int, List<String>>{};
    for (final reflection in await _dao.getAllActive()) {
      final pending = await _pendingImagesFor(
        reflection.id,
        _adapter.imageSources(reflection.contentJson),
      );
      if (pending.isNotEmpty) pendingByReflection[reflection.id] = pending;
    }
    final total = pendingByReflection.values.fold(
      0,
      (sum, pending) => sum + pending.length,
    );

    var done = 0;
    onProgress?.call(0, total);
    var report = const LocalImageSyncReport();
    for (final entry in pendingByReflection.entries) {
      report =
          report +
          await _downloadPendingImages(
            entry.key,
            entry.value,
            expectedGeneration,
            stopOnConsecutiveFailures: false,
            onEach: () => onProgress?.call(++done, total),
          );
    }
    return report;
  }

  /// 본문 이미지 중 아직 로컬에 없는 것(내려받아야 할 것)만 추린다.
  Future<List<String>> _pendingImagesFor(
    int reflectionId,
    List<String> sources,
  ) async {
    final linked = await _dao.findLocalImagePaths(reflectionId);
    return sources
        .toSet()
        .where(LocalImageStore.isRemote)
        .where((url) => !linked.containsKey(url))
        .where((url) => !_unavailableImageUrls.contains(url))
        .toList(growable: false);
  }

  /// 독후감 하나의 본문 이미지 중 아직 로컬에 없는 것을 받아 매칭에 더한다.
  Future<LocalImageSyncReport> _downloadImagesFor(
    int reflectionId,
    List<String> sources,
    int expectedGeneration,
  ) async {
    final pending = await _pendingImagesFor(reflectionId, sources);
    if (pending.isEmpty) return const LocalImageSyncReport();
    return _downloadPendingImages(reflectionId, pending, expectedGeneration);
  }

  Future<LocalImageSyncReport> _downloadPendingImages(
    int reflectionId,
    List<String> pending,
    int expectedGeneration, {
    bool stopOnConsecutiveFailures = true,
    void Function()? onEach,
  }) async {
    final mappings = Map<String, String>.from(
      await _dao.findLocalImagePaths(reflectionId),
    );
    var stored = 0;
    var unavailable = 0;
    var failed = 0;
    var consecutiveFailures = 0;
    for (final url in pending) {
      if (BookshelfDatabase.sessionGeneration != expectedGeneration) break;
      final result = await _imageStore.ensureDownloaded(url);
      switch (result.status) {
        case LocalImageDownloadStatus.failed:
          failed++;
          consecutiveFailures++;
        case LocalImageDownloadStatus.unavailable:
          consecutiveFailures = 0;
          unavailable++;
          if (_unavailableImageUrls.length < _maxUnavailableImageUrls) {
            _unavailableImageUrls.add(url);
          }
        case LocalImageDownloadStatus.stored:
          consecutiveFailures = 0;
          mappings[url] = result.localImagePath!;
          stored++;
      }
      onEach?.call();
      // 오프라인이면 앞선 몇 건이 연달아 실패한다. 특정 이미지 하나만 계속
      // 실패하는 경우에는 뒤의 이미지까지 막지 않는다.
      if (stopOnConsecutiveFailures &&
          consecutiveFailures >= _maxConsecutiveDownloadFailures) {
        break;
      }
    }
    if (stored > 0 &&
        BookshelfDatabase.sessionGeneration == expectedGeneration) {
      await _dao.replaceLocalImages(
        reflectionId: reflectionId,
        mappings: mappings,
      );
    }
    if (stored > 0 || failed > 0) {
      developer.log(
        '[독후감 이미지 로컬 저장] reflectionId=$reflectionId stored=$stored '
        'unavailable=$unavailable failed=$failed',
      );
    }
    return LocalImageSyncReport(
      stored: stored,
      unavailable: unavailable,
      failed: failed,
    );
  }

  /// 아직 로컬에 확보하지 못한 서버 이미지 수(다시 시도하면 받을 수 있는
  /// 것만). 로컬 저장 모드 전환 전 검증에 쓴다.
  Future<int> countImagesPendingDownload() async {
    var pending = 0;
    for (final reflection in await _dao.getAllActive()) {
      pending += (await _pendingImagesFor(
        reflection.id,
        _adapter.imageSources(reflection.contentJson),
      )).length;
    }
    return pending;
  }

  /// 네트워크를 타지 않는 로컬 파일 정리 — 사라진 독후감/본문에서 빠진
  /// 이미지/파일이 없어진 매칭을 끊고, 아무도 참조하지 않는 파일을 지운다.
  Future<void> sweepLocalImages() {
    return _sweepInFlight ??= _runSweep().whenComplete(
      () => _sweepInFlight = null,
    );
  }

  Future<void> _runSweep() async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    try {
      // 독후감이 사라졌는데 남은 매칭부터 정리한다(FK가 없어 동기화 삭제로는
      // 지워지지 않는다). 그러지 않으면 그 파일이 영원히 "쓰는 중"으로 남는다.
      await _dao.deleteOrphanLocalImages();

      final reflections = await _dao.getAllActive();
      final sourcesById = {
        for (final reflection in reflections)
          reflection.id: _adapter.imageSources(reflection.contentJson),
      };
      final fileNames = await _imageStore.listFileNames();
      final links = await _dao.getAllLocalImages();

      // 본문에서 빠졌거나 파일이 사라진 매칭을 끊는다 — 전자는 로컬 파일을
      // 정리 대상으로 풀어 주고, 후자는 다음 조회 때 다시 받게 한다.
      final linksByReflection = <int, List<ReflectionImageLink>>{};
      for (final link in links) {
        linksByReflection.putIfAbsent(link.reflectionId, () => []).add(link);
      }
      for (final entry in linksByReflection.entries) {
        final kept = {
          for (final link in entry.value)
            if ((sourcesById[entry.key]?.contains(link.remoteImageUrl) ??
                    false) &&
                fileNames.contains(_imageStore.fileNameOf(link.localImagePath)))
              link.remoteImageUrl: link.localImagePath,
        };
        if (kept.length == entry.value.length) continue;
        if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
        await _dao.replaceLocalImages(reflectionId: entry.key, mappings: kept);
      }

      if (BookshelfDatabase.sessionGeneration != expectedGeneration) return;
      await _pruneOrphanImages(sourcesById);
    } catch (error) {
      developer.log('[독후감 이미지 정리] result=FAIL reason=${_reasonOf(error)}');
    }
  }

  void _resetUnavailableIfSessionChanged(int generation) {
    if (_unavailableSessionGeneration == generation) return;
    _unavailableImageUrls.clear();
    _unavailableSessionGeneration = generation;
  }

  /// 어느 독후감도 참조하지 않는 이미지 파일을 지운다.
  ///
  /// 지켜야 할 파일은 세 갈래다 — 매칭이 걸린 사본, 아직 업로드되지 않아
  /// 본문이 로컬 경로로 직접 가리키는 사본, 그리고 이미 내려받았지만 아직
  /// 매칭되지 못한 사본(같은 URL은 항상 같은 파일명이라 다음에 그대로 다시
  /// 쓴다).
  Future<void> _pruneOrphanImages(Map<int, List<String>> sourcesById) async {
    final referenced = <String>[
      for (final link in await _dao.getAllLocalImages()) link.localImagePath,
    ];
    for (final sources in sourcesById.values) {
      for (final source in sources) {
        if (LocalImageStore.isRemote(source)) {
          final fileName = _imageStore.remoteFileNameOf(source);
          if (fileName != null) referenced.add(fileName);
        } else {
          referenced.add(source);
        }
      }
    }
    await _imageStore.pruneOrphans(referenced);
  }
}

/// [BookReflectionRepository._uploadPendingImages]의 결과.
class _ImageUploadResult {
  const _ImageUploadResult({
    required this.uploadedUrlBySource,
    required this.localImagePathBySource,
  });

  /// 이번에 업로드한 "본문의 로컬 경로 → 서버 URL".
  final Map<String, String> uploadedUrlBySource;

  /// "본문의 이미지 출처 → 로컬 사본 경로"(이번 업로드 + 기존 매칭).
  final Map<String, String> localImagePathBySource;
}
