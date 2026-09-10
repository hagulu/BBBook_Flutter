import 'dart:developer' as developer;

import '../../bookshelf/models/book_item.dart';
import '../../server_storage_migration/data/record_import_api.dart';
import '../../server_storage_migration/data/record_import_payload_builder.dart';
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

  Future<void> run(
    ExternalImportParseResult input, {
    Map<String, BookItem> existingBooksByIsbn = const {},
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
      throw ExternalImportException(
        validation,
        reason: 'import_preflight_failed',
      );
    }

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
      onProgress?.call(
        ExternalImportProgress(completed: 0, total: chunks.length + 1),
      );
      for (var index = 0; index < chunks.length; index++) {
        await api.uploadItems(session.importId, chunks[index].toJson());
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
        'importId=${session.importId} result=SUCCESS',
      );
    } catch (error) {
      if (session != null) {
        try {
          await api.cancel(session.importId);
        } catch (_) {
          // 서버가 요청 실패 시 이미 세션 전체를 정리했거나 네트워크가
          // 끊긴 경우다. 원래 오류를 사용자에게 전달한다.
        }
      }
      final reason = error is ExternalImportException
          ? error.reason
          : error is RecordImportException
          ? 'record_import_${error.kind.name}'
          : 'record_import_unknown';
      developer.log(
        '[외부 기록 가져오기] source=${input.source.code} '
        'importId=${session?.importId} result=FAIL reason=$reason',
      );
      if (error is ExternalImportException) rethrow;
      throw const ExternalImportException(
        '기록을 가져오지 못했어요. 잠시 후 다시 시도해 주세요.',
        reason: 'record_import_failed',
      );
    }
  }
}
