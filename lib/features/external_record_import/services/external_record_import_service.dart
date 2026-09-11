import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../book_note/models/book_note.dart';
import '../../bookshelf/models/book_item.dart';
import '../../server_storage_migration/data/record_import_api.dart';
import '../../server_storage_migration/data/record_import_payload_builder.dart';
import '../../server_storage_migration/data/record_import_snapshot.dart';
import '../../server_storage_migration/data/record_import_validation.dart';
import '../../server_storage_migration/models/record_import_models.dart';
import '../models/external_import_models.dart';
import 'external_import_snapshot_builder.dart';

class ExternalImportProgress {
  const ExternalImportProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  double get ratio => total == 0 ? 1 : completed / total;
}

class ExternalRecordImportResult {
  const ExternalRecordImportResult({required this.restoredBooksByIsbn});

  final Map<String, RestoredBookImportArtifacts> restoredBooksByIsbn;
}

/// 가져오기 직전에는 활성 책이 없었지만, 서버가 같은 ISBN의 삭제 행을
/// `created=false`로 복구한 책과 이번 Import로 그 책에 추가된 노트·메모다.
class RestoredBookImportArtifacts {
  const RestoredBookImportArtifacts({
    required this.bookServerId,
    required this.importedNoteServerIds,
    required this.importedNoteMemoServerIds,
  });

  final int bookServerId;
  final Set<int> importedNoteServerIds;
  final Set<int> importedNoteMemoServerIds;
}

class RestoredBookMemoCleanupPlan {
  const RestoredBookMemoCleanupPlan({
    required this.noteLocalIds,
    required this.memoTargets,
  });

  final List<int> noteLocalIds;
  final List<RestoredBookMemoCleanupTarget> memoTargets;
}

class RestoredBookMemoCleanupTarget {
  const RestoredBookMemoCleanupTarget({
    required this.noteLocalId,
    required this.memoLocalId,
    required this.previousLocalImagePath,
  });

  final int noteLocalId;
  final int memoLocalId;
  final String? previousLocalImagePath;
}

RestoredBookMemoCleanupPlan? buildRestoredBookMemoCleanupPlan({
  required RestoredBookImportArtifacts imported,
  required List<BookNoteSummary> summaries,
  required Map<int, BookNoteDetail> detailsByNoteLocalId,
}) {
  final activeServerNoteIds = summaries
      .map((summary) => summary.note.serverId)
      .whereType<int>()
      .toSet();
  if (!activeServerNoteIds.containsAll(imported.importedNoteServerIds)) {
    return null;
  }
  final activeImportedMemoServerIds = detailsByNoteLocalId.values
      .expand((detail) => detail.memos)
      .map((memo) => memo.serverId)
      .whereType<int>()
      .toSet();
  if (!activeImportedMemoServerIds.containsAll(
    imported.importedNoteMemoServerIds,
  )) {
    return null;
  }

  final noteLocalIds = <int>[];
  final memoTargets = <RestoredBookMemoCleanupTarget>[];
  for (final summary in summaries) {
    final note = summary.note;
    final serverNoteId = note.serverId;
    if (serverNoteId == null) continue;
    if (!imported.importedNoteServerIds.contains(serverNoteId)) {
      noteLocalIds.add(note.id);
      continue;
    }
    final detail = detailsByNoteLocalId[note.id];
    if (detail == null) continue;
    for (final memo in detail.memos) {
      final serverMemoId = memo.serverId;
      if (serverMemoId == null ||
          imported.importedNoteMemoServerIds.contains(serverMemoId)) {
        continue;
      }
      memoTargets.add(
        RestoredBookMemoCleanupTarget(
          noteLocalId: note.id,
          memoLocalId: memo.id,
          previousLocalImagePath: memo.localImagePath,
        ),
      );
    }
  }
  return RestoredBookMemoCleanupPlan(
    noteLocalIds: List.unmodifiable(noteLocalIds),
    memoTargets: List.unmodifiable(memoTargets),
  );
}

abstract class ExternalRecordImportGateway {
  Future<RecordImportSession> start();

  Future<RecordImportChunkResult> uploadItems(
    int importId,
    Map<String, dynamic> payload,
  );

  Future<void> complete(int importId, RecordImportCounts counts);

  Future<void> cancel(int importId);
}

class RecordImportApiGateway implements ExternalRecordImportGateway {
  const RecordImportApiGateway(this.api);

  final RecordImportApi api;

  @override
  Future<RecordImportSession> start() => api.start();

  @override
  Future<RecordImportChunkResult> uploadItems(
    int importId,
    Map<String, dynamic> payload,
  ) => api.uploadItems(importId, payload);

  @override
  Future<void> complete(int importId, RecordImportCounts counts) =>
      api.complete(importId, counts);

  @override
  Future<void> cancel(int importId) => api.cancel(importId);
}

class ExternalRecordImportService {
  const ExternalRecordImportService({
    required this.api,
    this.snapshotBuilder = const ExternalImportSnapshotBuilder(),
  });

  final ExternalRecordImportGateway api;
  final ExternalImportSnapshotBuilder snapshotBuilder;

  Future<ExternalRecordImportResult> run(
    ExternalImportParseResult input, {
    Map<String, BookItem> existingBooksByIsbn = const {},
    Set<String> overwriteExistingIsbns = const {},
    void Function(ExternalImportProgress progress)? onProgress,
  }) async {
    if (input.books.isEmpty) {
      throw const ExternalImportException(
        '가져올 수 있는 책 기록이 없어요.',
        reason: 'no_importable_books',
      );
    }
    final snapshot = snapshotBuilder.build(
      input,
      existingBooksByIsbn: existingBooksByIsbn,
      overwriteExistingIsbns: overwriteExistingIsbns,
    );
    final validation = validateRecordImportSnapshot(
      books: snapshot.books,
      notes: snapshot.notes,
      memos: snapshot.noteMemos,
      reflections: snapshot.reflections,
      tags: snapshot.tags,
      tagMaps: snapshot.tagMaps,
    );
    if (validation != null) {
      developer.log(
        '[외부 기록 가져오기 준비] source=${input.source.code} '
        '${_countLog(snapshot.counts)} result=FAIL '
        'reason=import_preflight_failed validation="$validation"',
      );
      throw ExternalImportException(
        validation,
        reason: 'import_preflight_failed',
      );
    }
    developer.log(
      '[외부 기록 가져오기 준비] source=${input.source.code} '
      '${_countLog(snapshot.counts)} overwriteCount=${overwriteExistingIsbns.length} '
      'result=SUCCESS',
    );

    RecordImportSession? session;
    try {
      session = await api.start();
      if (session.importedCount > 0) {
        await api.cancel(session.importId);
        session = await api.start();
      }
      final chunks = buildRecordImportChunks(
        books: snapshot.books
            .map(
              (book) => bookToImportJson(
                book,
                coverImageUrl: snapshot.coverImageUrlByBook[book.userBookId],
              ),
            )
            .toList(growable: false),
        tags: snapshot.tags.map(tagToImportJson).toList(growable: false),
        notes: snapshot.notes.map(noteToImportJson).toList(growable: false),
        noteMemos: snapshot.noteMemos
            .map(noteMemoToImportJson)
            .toList(growable: false),
        reflections: const [],
        tagMaps: snapshot.tagMaps
            .map(tagMapToImportJson)
            .toList(growable: false),
        maxChunkItemCount: session.maxChunkItemCount,
      );
      final bookResultsByLocalId = <int, RecordImportEntityResult>{};
      final noteResultsByLocalId = <int, RecordImportEntityResult>{};
      final memoResultsByLocalId = <int, RecordImportEntityResult>{};
      onProgress?.call(
        ExternalImportProgress(completed: 0, total: chunks.length + 1),
      );
      for (var index = 0; index < chunks.length; index++) {
        final chunk = chunks[index];
        final result = await api.uploadItems(session.importId, chunk.toJson());
        _collectChunkMappings(
          chunk,
          result,
          bookResultsByLocalId: bookResultsByLocalId,
          noteResultsByLocalId: noteResultsByLocalId,
          memoResultsByLocalId: memoResultsByLocalId,
        );
        onProgress?.call(
          ExternalImportProgress(
            completed: index + 1,
            total: chunks.length + 1,
          ),
        );
      }
      await api.complete(session.importId, snapshot.counts);
      onProgress?.call(
        ExternalImportProgress(
          completed: chunks.length + 1,
          total: chunks.length + 1,
        ),
      );
      developer.log(
        '[외부 기록 가져오기] source=${input.source.code} '
        'importId=${session.importId} ${_countLog(snapshot.counts)} '
        'result=SUCCESS',
      );
      return _buildResult(
        snapshot,
        existingBooksByIsbn,
        bookResultsByLocalId,
        noteResultsByLocalId,
        memoResultsByLocalId,
      );
    } catch (error, stackTrace) {
      if (session != null && _requiresClientCancel(error)) {
        try {
          await api.cancel(session.importId);
        } catch (_) {
          // 클라이언트 후처리 실패로 취소를 요청했지만 네트워크가 끊겼을
          // 수 있다. 원래 오류를 사용자에게 전달하고 TTL 정리에 맡긴다.
        }
      }
      final reason = error is ExternalImportException
          ? error.reason
          : error is RecordImportException
          ? 'record_import_${error.kind.name}'
          : 'record_import_unknown';
      final errorContext = switch (error) {
        RecordImportException value =>
          'status=${value.statusCode}'
              '${kDebugMode && value.serverMessage != null ? ' serverMessage="${_logValue(value.serverMessage!)}"' : ''} ',
        _ => 'exception=${error.runtimeType} ',
      };
      developer.log(
        '[외부 기록 가져오기] source=${input.source.code} '
        'importId=${session?.importId} $errorContext'
        'result=FAIL reason=$reason',
        error: kDebugMode ? error : null,
        stackTrace: kDebugMode ? stackTrace : null,
      );
      if (error is ExternalImportException) rethrow;
      if (error is RecordImportException) {
        throw ExternalImportException(_userMessage(error), reason: reason);
      }
      throw const ExternalImportException(
        '기록을 가져오지 못했어요. 잠시 후 다시 시도해 주세요.',
        reason: 'record_import_failed',
      );
    }
  }

  void _collectChunkMappings(
    RecordImportChunk chunk,
    RecordImportChunkResult result, {
    required Map<int, RecordImportEntityResult> bookResultsByLocalId,
    required Map<int, RecordImportEntityResult> noteResultsByLocalId,
    required Map<int, RecordImportEntityResult> memoResultsByLocalId,
  }) {
    if (!_hasExactLocalIds(chunk.books, result.books) ||
        !_hasExactLocalIds(chunk.notes, result.notes) ||
        !_hasExactLocalIds(chunk.noteMemos, result.noteMemos) ||
        !_hasExactLocalIds(chunk.reflections, result.reflections) ||
        !_hasExactLocalIds(chunk.tags, result.tags) ||
        !_hasExactLocalIds(chunk.tagMaps, result.tagMaps)) {
      throw const ExternalImportException(
        '가져오기 결과를 확인하지 못했어요. 다시 시도해 주세요.',
        reason: 'record_import_mapping_mismatch',
      );
    }

    for (final entity in result.books) {
      bookResultsByLocalId[entity.localId] = entity;
    }
    for (final entity in result.notes) {
      noteResultsByLocalId[entity.localId] = entity;
    }
    for (final entity in result.noteMemos) {
      memoResultsByLocalId[entity.localId] = entity;
    }
  }

  bool _hasExactLocalIds(
    List<Map<String, dynamic>> requested,
    List<RecordImportEntityResult> returned,
  ) {
    if (requested.length != returned.length) return false;
    final requestedIds = <int>{};
    for (final item in requested) {
      final localId = item['localId'];
      if (localId is! int || !requestedIds.add(localId)) return false;
    }
    final returnedIds = <int>{};
    for (final item in returned) {
      if (!returnedIds.add(item.localId)) return false;
    }
    return requestedIds.length == returnedIds.length &&
        requestedIds.containsAll(returnedIds);
  }

  ExternalRecordImportResult _buildResult(
    RecordImportSnapshot snapshot,
    Map<String, BookItem> existingBooksByIsbn,
    Map<int, RecordImportEntityResult> bookResultsByLocalId,
    Map<int, RecordImportEntityResult> noteResultsByLocalId,
    Map<int, RecordImportEntityResult> memoResultsByLocalId,
  ) {
    final createdBookServerIds = bookResultsByLocalId.values
        .where((result) => result.created)
        .map((result) => result.serverId)
        .toSet();
    final noteBookLocalIdByNoteLocalId = {
      for (final note in snapshot.notes) note.id: note.userBookId,
    };
    final noteServerIdsByBookLocalId = <int, Set<int>>{};
    for (final note in snapshot.notes) {
      final result = noteResultsByLocalId[note.id];
      if (result == null) continue;
      noteServerIdsByBookLocalId
          .putIfAbsent(note.userBookId, () => <int>{})
          .add(result.serverId);
    }
    final memoServerIdsByBookLocalId = <int, Set<int>>{};
    for (final memo in snapshot.noteMemos) {
      final bookLocalId = noteBookLocalIdByNoteLocalId[memo.noteId];
      final result = memoResultsByLocalId[memo.id];
      if (bookLocalId == null || result == null) continue;
      memoServerIdsByBookLocalId
          .putIfAbsent(bookLocalId, () => <int>{})
          .add(result.serverId);
    }

    final restored = <String, RestoredBookImportArtifacts>{};
    for (final book in snapshot.books) {
      final isbn13 = book.isbn13;
      final result = bookResultsByLocalId[book.userBookId];
      if (isbn13 == null ||
          result == null ||
          result.created ||
          book.serverId != null ||
          existingBooksByIsbn.containsKey(isbn13) ||
          createdBookServerIds.contains(result.serverId)) {
        continue;
      }
      restored[isbn13] = RestoredBookImportArtifacts(
        bookServerId: result.serverId,
        importedNoteServerIds: Set.unmodifiable(
          noteServerIdsByBookLocalId[book.userBookId] ?? const {},
        ),
        importedNoteMemoServerIds: Set.unmodifiable(
          memoServerIdsByBookLocalId[book.userBookId] ?? const {},
        ),
      );
    }

    return ExternalRecordImportResult(
      restoredBooksByIsbn: Map.unmodifiable(restored),
    );
  }

  String _userMessage(RecordImportException error) {
    if (error.kind == RecordImportFailureKind.network) {
      return '네트워크 연결을 확인한 뒤 다시 시도해 주세요.';
    }
    if (error.serverMessage case final serverMessage?) {
      return serverMessage;
    }
    return switch (error.kind) {
      RecordImportFailureKind.sessionNotFound ||
      RecordImportFailureKind.sessionExpired => '가져오기 시간이 만료되었어요. 다시 시도해 주세요.',
      _ => '기록을 가져오지 못했어요. 잠시 후 다시 시도해 주세요.',
    };
  }

  bool _requiresClientCancel(Object error) {
    if (error is! RecordImportException) return true;

    // items/attachments/complete 요청 실패는 서버가 세션 전체를 자동으로
    // 정리한다. 응답을 받지 못한 네트워크 실패도 다음 start/TTL 정리로
    // 복구하므로, 즉시 cancel을 덧붙여 원래 실패 로그를 흐리지 않는다.
    // 다만 HTTP 성공 응답의 구조를 앱이 해석하지 못한 경우에는 서버가
    // 자동 정리하지 않았으므로 클라이언트가 명시적으로 취소해야 한다.
    return error.kind == RecordImportFailureKind.unknown &&
        error.statusCode == null &&
        error.cause == null;
  }

  String _countLog(RecordImportCounts counts) {
    return 'bookCount=${counts.bookCount} '
        'noteCount=${counts.noteCount} '
        'noteMemoCount=${counts.noteMemoCount} '
        'reflectionCount=${counts.reflectionCount} '
        'tagCount=${counts.tagCount} '
        'tagMapCount=${counts.tagMapCount}';
  }

  String _logValue(String value) {
    final singleLine = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return singleLine.length <= 300
        ? singleLine
        : '${singleLine.substring(0, 300)}…';
  }
}
