import 'dart:developer' as developer;

import '../../bookshelf/data/bookshelf_database.dart';
import 'record_sync_api.dart';
import 'record_sync_dao.dart';

class RecordSyncRepository {
  const RecordSyncRepository(this._api, [this._dao = const RecordSyncDao()]);

  final RecordSyncApi _api;
  final RecordSyncDao _dao;

  Future<bool> isInitialSyncCompleted(int userId) {
    return _dao.isInitialSyncCompleted(userId);
  }

  Future<void> synchronize({
    required int userId,
    required void Function() onDownloadStarted,
    required RecordSaveProgress onSaveProgress,
  }) async {
    final expectedGeneration = BookshelfDatabase.sessionGeneration;
    final requestedAt = DateTime.now().toUtc();
    onDownloadStarted();
    final payload = await _api.getAllRecords();
    if (BookshelfDatabase.sessionGeneration != expectedGeneration) {
      throw const RecordSyncSessionChanged();
    }

    try {
      onSaveProgress(0, payload.totalItemCount);
      await _dao.replaceInitialRecords(
        userId: userId,
        expectedSessionGeneration: expectedGeneration,
        requestedAt: requestedAt,
        payload: payload,
        onProgress: onSaveProgress,
      );
      developer.log(
        '[초기 기록 저장] userId=$userId count=${payload.totalItemCount} '
        'result=SUCCESS',
      );
    } catch (e) {
      developer.log(
        '[초기 기록 저장] userId=$userId result=FAIL '
        'reason=${e is RecordSyncSessionChanged ? "session_changed" : "database"}',
      );
      rethrow;
    }
  }
}
