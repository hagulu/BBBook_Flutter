import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../../core/network/api_exception.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../bookshelf/data/bookshelf_repository.dart';
import '../../record_sync/data/record_sync_api.dart';
import '../models/book_reflection.dart';
import 'book_reflection_api.dart';
import 'book_reflection_dao.dart';

/// 독후감 화면의 source of truth.
///
/// 화면은 항상 이 Repository를 통해 로컬 DB를 읽고 쓴다. 작성/수정은 로컬에
/// 즉시 반영한 뒤 dirty push하고, 실패한 행은 다음 [sync]에서 재시도한다.
class BookReflectionRepository {
  BookReflectionRepository({
    required this._api,
    required this._recordSyncApi,
    required this._bookshelfRepository,
    this._dao = const BookReflectionDao(),
  });

  final BookReflectionApi _api;
  final RecordSyncApi _recordSyncApi;
  final BookshelfRepository _bookshelfRepository;
  final BookReflectionDao _dao;
  final Map<int, Future<void>> _dirtyPushChains = {};

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
      if (current.serverId != null) {
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

  Future<String> uploadImage(String filePath) async {
    final file = File(filePath);
    final extension = path
        .extension(filePath)
        .replaceFirst('.', '')
        .toLowerCase();
    if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
      throw const ApiException('JPEG, PNG, WEBP 이미지만 첨부할 수 있습니다.');
    }
    if (!await file.exists()) {
      throw const ApiException('선택한 이미지를 찾을 수 없습니다.');
    }
    if (await file.length() > 5 * 1024 * 1024) {
      throw const ApiException('이미지는 5MB 이하만 첨부할 수 있습니다.');
    }
    try {
      final url = await _api.uploadTempImage(file);
      developer.log('[독후감 이미지 업로드] result=SUCCESS');
      return url;
    } catch (error) {
      developer.log('[독후감 이미지 업로드] result=FAIL reason=${_reasonOf(error)}');
      rethrow;
    }
  }

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
    final expectedGeneration = BookshelfDatabase.sessionGeneration;

    await pushAllDirty();
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      return false;
    }

    final since = await _dao.getLastSyncedAtReflection();
    if (since == null) {
      return _fullSync(ownerUserId, expectedGeneration);
    }

    final result = await _api.getSyncChanges(since: since);
    if (result.fullSyncRequired) {
      // 증분 응답의 syncedAt(서버 시각)을 기준값으로 쓴다 — 클라이언트
      // now()를 쓰면 기기 시계가 서버보다 앞서 있을 때 그 오차만큼 이후
      // 서버 변경을 영구히 놓칠 수 있다.
      return _fullSync(
        ownerUserId,
        expectedGeneration,
        baseline: result.syncedAt,
      );
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
    final draft = BookReflectionDraft(
      title: title,
      contentJson: contentJson,
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
      await _dao.confirmPush(
        localId: localReflectionId,
        capturedUpdatedAt: reflection.updatedAt,
        result: result,
      );
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
}
