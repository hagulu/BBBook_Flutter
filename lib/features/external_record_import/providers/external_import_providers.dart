import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_notifier.dart';
import '../../book_note/providers/book_note_providers.dart';
import '../../book_reflection/providers/book_reflection_providers.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../server_storage_migration/providers/server_storage_migration_providers.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../../tag/providers/tag_providers.dart';
import '../models/external_import_models.dart';
import '../services/external_import_file_analyzer.dart';
import '../services/external_record_import_service.dart';

final externalImportFileAnalyzerProvider = Provider<ExternalImportFileAnalyzer>(
  (_) => const ExternalImportFileAnalyzer(),
);

final externalRecordImportServiceProvider =
    Provider<ExternalRecordImportService>(
      (ref) => ExternalRecordImportService(
        api: RecordImportApiGateway(ref.watch(recordImportApiProvider)),
      ),
    );

class ExternalImportExecutionLock extends Notifier<int?> {
  Object? _owner;

  @override
  int? build() => null;

  bool tryAcquire({required int userId, required Object owner}) {
    if (_owner != null) return false;
    _owner = owner;
    state = userId;
    return true;
  }

  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    state = null;
  }
}

final externalImportExecutionLockProvider =
    NotifierProvider<ExternalImportExecutionLock, int?>(
      ExternalImportExecutionLock.new,
    );

enum ExternalImportPhase { analyzing, ready, importing, completed, failed }

class ExternalImportState {
  const ExternalImportState({
    this.phase = ExternalImportPhase.analyzing,
    this.result,
    this.message,
    this.progress,
  });

  final ExternalImportPhase phase;
  final ExternalImportParseResult? result;
  final String? message;
  final ExternalImportProgress? progress;

  ExternalImportState copyWith({
    ExternalImportPhase? phase,
    ExternalImportParseResult? result,
    String? message,
    ExternalImportProgress? progress,
    bool clearMessage = false,
  }) {
    return ExternalImportState(
      phase: phase ?? this.phase,
      result: result ?? this.result,
      message: clearMessage ? null : message ?? this.message,
      progress: progress ?? this.progress,
    );
  }
}

class ExternalImportController
    extends
        AutoDisposeFamilyNotifier<
          ExternalImportState,
          ExternalImportFileReference
        > {
  var _disposed = false;

  @override
  ExternalImportState build(ExternalImportFileReference reference) {
    ref.onDispose(() => _disposed = true);
    Future.microtask(_analyze);
    return const ExternalImportState();
  }

  Future<void> _analyze() async {
    try {
      final result = await ref
          .read(externalImportFileAnalyzerProvider)
          .analyze(arg);
      if (_disposed) return;
      state = ExternalImportState(
        phase: ExternalImportPhase.ready,
        result: result,
      );
      developer.log(
        '[외부 파일 분석] source=${result.source.code} '
        'result=SUCCESS',
      );
    } on ExternalImportException catch (error) {
      developer.log('[외부 파일 분석] result=FAIL reason=${error.reason}');
      if (_disposed) return;
      state = ExternalImportState(
        phase: ExternalImportPhase.failed,
        message: error.userMessage,
      );
    } catch (_) {
      developer.log('[외부 파일 분석] result=FAIL reason=unexpected_error');
      if (_disposed) return;
      state = const ExternalImportState(
        phase: ExternalImportPhase.failed,
        message: '파일을 분석하지 못했어요. 파일을 확인한 뒤 다시 시도해 주세요.',
      );
    }
  }

  Future<String?> startImport() async {
    final input = state.result;
    if (input == null || state.phase == ExternalImportPhase.importing) {
      return null;
    }
    if (ref.read(localStorageMigrationControllerProvider).isRunning ||
        ref.read(serverStorageMigrationControllerProvider).isRunning) {
      return '저장 방식 변경이 끝난 뒤 다시 시도해 주세요.';
    }
    final ownerUserId = ref.read(authNotifierProvider).user?.id;
    if (ownerUserId == null) return '로그인 상태를 확인해 주세요.';
    final executionLock = ref.read(
      externalImportExecutionLockProvider.notifier,
    );
    if (!executionLock.tryAcquire(userId: ownerUserId, owner: this)) {
      return '다른 기록을 가져오는 중이에요. 완료된 뒤 다시 시도해 주세요.';
    }
    final generation = BookshelfDatabase.sessionGeneration;

    try {
      final mode = await ref.read(storageModeStoreProvider).current();
      if (mode == StorageMode.local) {
        return '현재 동기화가 꺼져 있어요. 설정에서 동기화를 켠 뒤 가져와 주세요.';
      }
      state = state.copyWith(
        phase: ExternalImportPhase.importing,
        clearMessage: true,
      );
      // 기존 로컬 편집을 먼저 서버에 반영한 뒤 같은 ISBN의 기존 책을 찾아,
      // Import payload가 그 책의 기록과 설정을 그대로 보존하도록 한다.
      await ref
          .read(bookshelfSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      await ref
          .read(bookNoteSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      await ref
          .read(bookReflectionSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      await ref.read(tagSyncControllerProvider.notifier).syncNow();
      _checkSession(ownerUserId, generation);
      if (!_allSyncsHealthy()) {
        throw const ExternalImportException(
          '기존 기록을 동기화하지 못했어요. 네트워크를 확인한 뒤 다시 시도해 주세요.',
          reason: 'pre_import_sync_failed',
        );
      }
      final existingBooksByIsbn = await _loadExistingBooks(input);
      _checkSession(ownerUserId, generation);

      await ref
          .read(externalRecordImportServiceProvider)
          .run(
            input,
            existingBooksByIsbn: existingBooksByIsbn,
            onProgress: (progress) {
              if (_disposed) return;
              state = state.copyWith(progress: progress);
            },
          );
      _checkSession(ownerUserId, generation);

      await ref
          .read(bookshelfSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      await ref
          .read(bookNoteSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      await ref
          .read(bookReflectionSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      await ref.read(tagSyncControllerProvider.notifier).syncNow();
      final refreshed = _allSyncsHealthy();
      if (!refreshed) {
        developer.log(
          '[외부 기록 동기화] userId=$ownerUserId '
          'result=FAIL reason=local_refresh_failed',
        );
      }
      if (_disposed) return null;
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
      ref.read(bookNoteSyncVersionProvider.notifier).state++;
      ref.read(bookReflectionSyncVersionProvider.notifier).state++;
      ref.read(tagSyncVersionProvider.notifier).state++;
      state = state.copyWith(
        phase: ExternalImportPhase.completed,
        message: refreshed ? '기록을 가져왔어요.' : '기록은 가져왔지만 목록 새로고침이 필요해요.',
      );
      return null;
    } on ExternalImportException catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          phase: ExternalImportPhase.ready,
          message: error.userMessage,
        );
      }
      return error.userMessage;
    } on _ExternalImportSessionChanged {
      const message = '계정 상태가 변경되어 가져오기를 중단했어요.';
      if (!_disposed) {
        state = state.copyWith(
          phase: ExternalImportPhase.ready,
          message: message,
        );
      }
      return message;
    } catch (_) {
      const message = '기록을 가져오지 못했어요. 잠시 후 다시 시도해 주세요.';
      if (!_disposed) {
        state = state.copyWith(
          phase: ExternalImportPhase.ready,
          message: message,
        );
      }
      return message;
    } finally {
      executionLock.release(this);
    }
  }

  Future<Map<String, BookItem>> _loadExistingBooks(
    ExternalImportParseResult input,
  ) async {
    final isbns = input.books
        .map((book) => book.isbn13)
        .whereType<String>()
        .toSet();
    final repository = ref.read(bookshelfRepositoryProvider);
    final entries = await Future.wait(
      isbns.map(
        (isbn) async => MapEntry(isbn, await repository.getByIsbn13(isbn)),
      ),
    );
    return {
      for (final entry in entries)
        if (entry.value != null) entry.key: entry.value!,
    };
  }

  void _checkSession(int ownerUserId, int generation) {
    if (generation != BookshelfDatabase.sessionGeneration ||
        ref.read(authNotifierProvider).user?.id != ownerUserId) {
      throw const _ExternalImportSessionChanged();
    }
  }

  bool _allSyncsHealthy() {
    return !ref.read(bookshelfSyncControllerProvider).hasError &&
        !ref.read(bookNoteSyncControllerProvider).hasError &&
        !ref.read(bookReflectionSyncControllerProvider).hasError &&
        !ref.read(tagSyncControllerProvider).hasError;
  }
}

class _ExternalImportSessionChanged implements Exception {
  const _ExternalImportSessionChanged();
}

final externalImportControllerProvider = NotifierProvider.autoDispose
    .family<
      ExternalImportController,
      ExternalImportState,
      ExternalImportFileReference
    >(ExternalImportController.new);
