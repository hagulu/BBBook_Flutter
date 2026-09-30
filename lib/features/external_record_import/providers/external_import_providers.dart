import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_access_providers.dart';
import '../../book_note/models/book_note.dart';
import '../../book_note/providers/book_note_providers.dart';
import '../../book_reflection/providers/book_reflection_providers.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../bookshelf/models/book_item.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../record_archive/data/record_archive_dao.dart';
import '../../server_storage_migration/providers/server_storage_migration_providers.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../../tag/providers/tag_providers.dart';
import '../models/external_import_models.dart';
import '../services/external_import_file_analyzer.dart';
import '../services/external_record_import_service.dart';
import '../services/external_record_local_import_service.dart';

final externalImportFileAnalyzerProvider = Provider<ExternalImportFileAnalyzer>(
  (_) => const ExternalImportFileAnalyzer(),
);

final externalRecordImportServiceProvider =
    Provider<ExternalRecordImportService>(
      (ref) => ExternalRecordImportService(
        api: RecordImportApiGateway(ref.watch(recordImportApiProvider)),
      ),
    );

final externalRecordLocalImportServiceProvider =
    Provider<ExternalRecordLocalImportService>(
      (_) => ExternalRecordLocalImportService(dao: RecordArchiveDao()),
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

enum ExternalImportFeedbackType { info, error }

class ExternalImportFeedback {
  const ExternalImportFeedback.info(this.message)
    : type = ExternalImportFeedbackType.info;

  const ExternalImportFeedback.error(this.message)
    : type = ExternalImportFeedbackType.error;

  final String message;
  final ExternalImportFeedbackType type;
}

class ExternalImportState {
  const ExternalImportState({
    this.phase = ExternalImportPhase.analyzing,
    this.result,
    this.message,
    this.progress,
    this.selectedBookIndexes = const {},
    this.conflictingBookIndexes = const {},
    this.overwriteBookIndexes = const {},
    this.needsRefresh = false,
  });

  final ExternalImportPhase phase;
  final ExternalImportParseResult? result;
  final String? message;
  final ExternalImportProgress? progress;
  final Set<int> selectedBookIndexes;
  final Set<int> conflictingBookIndexes;
  final Set<int> overwriteBookIndexes;
  final bool needsRefresh;

  int get selectedBookCount => selectedBookIndexes.length;

  ExternalImportState copyWith({
    ExternalImportPhase? phase,
    ExternalImportParseResult? result,
    String? message,
    ExternalImportProgress? progress,
    Set<int>? selectedBookIndexes,
    Set<int>? conflictingBookIndexes,
    Set<int>? overwriteBookIndexes,
    bool? needsRefresh,
    bool clearMessage = false,
  }) {
    return ExternalImportState(
      phase: phase ?? this.phase,
      result: result ?? this.result,
      message: clearMessage ? null : message ?? this.message,
      progress: progress ?? this.progress,
      selectedBookIndexes: selectedBookIndexes ?? this.selectedBookIndexes,
      conflictingBookIndexes:
          conflictingBookIndexes ?? this.conflictingBookIndexes,
      overwriteBookIndexes: overwriteBookIndexes ?? this.overwriteBookIndexes,
      needsRefresh: needsRefresh ?? this.needsRefresh,
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
      final existingBooksByIsbn = await _loadExistingBooks(result);
      final conflicts = _conflictingIndexes(result, existingBooksByIsbn);
      // 파일 안에 같은 ISBN 항목이 여럿이면 첫 항목만 기본 선택한다.
      final seenIsbns = <String>{};
      final selected = {
        for (var index = 0; index < result.books.length; index++)
          if (!conflicts.contains(index) &&
              (result.books[index].isbn13 == null ||
                  seenIsbns.add(result.books[index].isbn13!)))
            index,
      };
      if (_disposed) return;
      state = ExternalImportState(
        phase: ExternalImportPhase.ready,
        result: result,
        selectedBookIndexes: Set.unmodifiable(selected),
        conflictingBookIndexes: Set.unmodifiable(conflicts),
      );
      developer.log(
        '[외부 파일 분석] source=${result.source.code} '
        'conflictCount=${conflicts.length} '
        'result=SUCCESS',
      );
    } on ExternalImportException catch (error) {
      developer.log('[외부 파일 분석] result=FAIL reason=${error.reason}');
      if (_disposed) return;
      state = ExternalImportState(
        phase: ExternalImportPhase.failed,
        message: error.userMessage,
      );
    } catch (error, stackTrace) {
      developer.log(
        '[외부 파일 분석] exception=${error.runtimeType} '
        'result=FAIL reason=unexpected_error',
        error: kDebugMode ? error : null,
        stackTrace: kDebugMode ? stackTrace : null,
      );
      if (_disposed) return;
      state = const ExternalImportState(
        phase: ExternalImportPhase.failed,
        message: '파일을 분석하지 못했어요. 파일을 확인한 뒤 다시 시도해 주세요.',
      );
    }
  }

  void toggleBookSelection(int index) {
    if (state.phase != ExternalImportPhase.ready ||
        index < 0 ||
        index >= (state.result?.books.length ?? 0)) {
      return;
    }
    final selected = state.selectedBookIndexes.toSet();
    final overwrites = state.overwriteBookIndexes.toSet();
    if (!selected.add(index)) {
      selected.remove(index);
      overwrites.remove(index);
    } else if (state.conflictingBookIndexes.contains(index)) {
      overwrites.add(index);
    }
    state = state.copyWith(
      selectedBookIndexes: Set.unmodifiable(selected),
      overwriteBookIndexes: Set.unmodifiable(overwrites),
      clearMessage: true,
    );
  }

  Future<ExternalImportFeedback?> startImport() async {
    final input = state.result;
    if (input == null || state.phase == ExternalImportPhase.importing) {
      return null;
    }
    if (state.selectedBookIndexes.isEmpty) {
      return const ExternalImportFeedback.info('가져올 책을 한 권 이상 선택해 주세요.');
    }
    // 같은 ISBN 두 항목은 서버 Import에서는 세션 전체 실패(400), 로컬
    // 저장에서는 한 권으로 합쳐져 앞 항목이 사라진다. 저장 전에 막는다.
    final selectedIsbns = <String>{};
    for (final index in state.selectedBookIndexes) {
      final isbn13 = input.books[index].isbn13;
      if (isbn13 != null && !selectedIsbns.add(isbn13)) {
        return const ExternalImportFeedback.info(
          '같은 책(ISBN)이 두 번 이상 선택됐어요. 한 항목만 선택해 주세요.',
        );
      }
    }
    if (ref.read(localStorageMigrationControllerProvider).isRunning ||
        ref.read(serverStorageMigrationControllerProvider).isRunning) {
      return const ExternalImportFeedback.info('저장 방식 변경이 끝난 뒤 다시 시도해 주세요.');
    }
    final ownerUserId = ref.read(recordOwnerIdProvider);
    if (ownerUserId == null) {
      return const ExternalImportFeedback.error('로그인 상태를 확인해 주세요.');
    }
    final executionLock = ref.read(
      externalImportExecutionLockProvider.notifier,
    );
    if (!executionLock.tryAcquire(userId: ownerUserId, owner: this)) {
      return const ExternalImportFeedback.info(
        '다른 기록을 가져오는 중이에요. 완료된 뒤 다시 시도해 주세요.',
      );
    }
    final keepAliveLink = ref.keepAlive();
    final generation = BookshelfDatabase.sessionGeneration;
    var stage = 'storage_mode_check';
    var importCommitted = false;

    try {
      // 동기화가 켜져 있으면 서버 Import를 먼저 거친다(같은 ISBN 재사용·삭제
      // 행 복구·전체 롤백·원래 날짜 보존). 서버를 쓰지 않는 경우에만 로컬
      // DB에 바로 저장한다.
      final mode = await ref.read(storageModeStoreProvider).current();
      if (!ref.read(canUseAccountFeaturesProvider) ||
          mode == StorageMode.local) {
        stage = 'local_import';
        return await _importLocally(input, ownerUserId, generation);
      }
      state = state.copyWith(
        phase: ExternalImportPhase.importing,
        clearMessage: true,
        needsRefresh: false,
      );
      developer.log(
        '[외부 기록 가져오기 시작] userId=$ownerUserId '
        'source=${input.source.code} selectedBookCount=${state.selectedBookCount} '
        'overwriteCount=${state.overwriteBookIndexes.length} result=SUCCESS',
      );
      // 기존 로컬 편집을 먼저 서버에 반영한 뒤 같은 ISBN의 기존 책을 다시
      // 확인한다. 목록에서 명시적으로 덮어쓰기를 고르지 않은 충돌은 이
      // 시점에도 자동 제외해, 분석 이후 생긴 변경을 조용히 덮지 않는다.
      stage = 'pre_import_bookshelf_sync';
      await ref
          .read(bookshelfSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      stage = 'pending_delete_flush';
      final selectedIsbns = state.selectedBookIndexes
          .map((index) => input.books[index].isbn13)
          .whereType<String>();
      final deletesFlushed = await ref
          .read(bookshelfRepositoryProvider)
          .flushPendingDeletesForIsbns(selectedIsbns);
      if (!deletesFlushed) {
        throw const ExternalImportException(
          '방금 삭제한 책을 서버에 반영하고 있어요. 잠시 후 다시 시도해 주세요.',
          reason: 'pending_book_delete',
        );
      }
      // 첫 호출이 삭제보다 먼저 시작된 백그라운드 동기화와 합류했을 수
      // 있다. 삭제 push가 끝난 뒤 새 요청을 한 번 더 보내 로컬 tombstone까지
      // 정리해야 Import가 같은 ISBN 책을 안전하게 복구할 수 있다.
      stage = 'post_delete_bookshelf_sync';
      await ref
          .read(bookshelfSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      stage = 'pre_import_note_sync';
      await ref
          .read(bookNoteSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      stage = 'pre_import_reflection_sync';
      await ref
          .read(bookReflectionSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      stage = 'pre_import_tag_sync';
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

      final selection = _confirmSelection(input, existingBooksByIsbn);
      if (selection == null) return _newConflictFeedback;
      final selectedBooks = selection.input.books;
      final overwriteExistingIsbns = selection.overwriteExistingIsbns;
      final selectedInput = selection.input;

      stage = 'record_import';
      final importResult = await ref
          .read(externalRecordImportServiceProvider)
          .run(
            selectedInput,
            existingBooksByIsbn: existingBooksByIsbn,
            overwriteExistingIsbns: overwriteExistingIsbns,
            onProgress: (progress) {
              if (_disposed) return;
              state = state.copyWith(progress: progress);
            },
          );
      importCommitted = true;
      _checkSession(ownerUserId, generation);

      stage = 'post_import_bookshelf_sync';
      await ref
          .read(bookshelfSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      stage = 'post_import_note_sync';
      await ref
          .read(bookNoteSyncControllerProvider.notifier)
          .syncNow(userInitiated: true, forceFullSync: true);
      stage = 'restored_memo_cleanup';
      final canCleanRestoredMemos = _bookAndNoteSyncsHealthy();
      if (!canCleanRestoredMemos &&
          importResult.restoredBooksByIsbn.isNotEmpty) {
        developer.log(
          '[외부 기록 복구 메모 정리] result=SKIP '
          'reason=post_import_sync_failed',
        );
      }
      final cleanup = canCleanRestoredMemos
          ? await _removeRestoredBookMemos(
              ownerUserId: ownerUserId,
              result: importResult,
            )
          : (deletedNoteCount: 0, deletedMemoCount: 0);
      if (cleanup.deletedNoteCount > 0 || cleanup.deletedMemoCount > 0) {
        stage = 'post_cleanup_note_push';
        await ref.read(bookNoteRepositoryProvider).pushAllDirty();
      }
      stage = 'post_import_reflection_sync';
      await ref
          .read(bookReflectionSyncControllerProvider.notifier)
          .syncNow(userInitiated: true);
      stage = 'post_import_tag_sync';
      await ref.read(tagSyncControllerProvider.notifier).syncNow();
      final refreshed = _allSyncsHealthy();
      if (!refreshed) {
        developer.log(
          '[외부 기록 동기화] userId=$ownerUserId '
          'result=FAIL reason=local_refresh_failed',
        );
      }
      _completeImport(
        selectedBookCount: selectedBooks.length,
        needsRefresh: !refreshed,
      );
      developer.log(
        '[외부 기록 가져오기 흐름] userId=$ownerUserId '
        'source=${input.source.code} stage=completed '
        'selectedBookCount=${selectedBooks.length} result=SUCCESS',
      );
      return null;
    } on ExternalImportException catch (error) {
      developer.log(
        '[외부 기록 가져오기 흐름] userId=$ownerUserId '
        'source=${input.source.code} stage=$stage result=FAIL '
        'reason=${error.reason}',
      );
      if (importCommitted) {
        _completeImport(
          selectedBookCount: state.selectedBookCount,
          needsRefresh: true,
        );
        return null;
      }
      if (!_disposed) {
        state = state.copyWith(
          phase: ExternalImportPhase.ready,
          message: error.userMessage,
        );
      }
      return ExternalImportFeedback.error(error.userMessage);
    } on _ExternalImportSessionChanged {
      const message = '계정 상태가 변경되어 가져오기를 중단했어요.';
      developer.log(
        '[외부 기록 가져오기 흐름] userId=$ownerUserId '
        'source=${input.source.code} stage=$stage result=FAIL '
        'reason=session_changed',
      );
      if (!_disposed) {
        state = state.copyWith(
          phase: ExternalImportPhase.ready,
          message: message,
        );
      }
      return const ExternalImportFeedback.error(message);
    } catch (error, stackTrace) {
      const message = '기록을 가져오지 못했어요. 잠시 후 다시 시도해 주세요.';
      developer.log(
        '[외부 기록 가져오기 흐름] userId=$ownerUserId '
        'source=${input.source.code} stage=$stage result=FAIL '
        'reason=unexpected_error exception=${error.runtimeType}',
        error: kDebugMode ? error : null,
        stackTrace: kDebugMode ? stackTrace : null,
      );
      if (importCommitted) {
        _completeImport(
          selectedBookCount: state.selectedBookCount,
          needsRefresh: true,
        );
        return null;
      }
      if (!_disposed) {
        state = state.copyWith(
          phase: ExternalImportPhase.ready,
          message: message,
        );
      }
      return const ExternalImportFeedback.error(message);
    } finally {
      executionLock.release(this);
      keepAliveLink.close();
    }
  }

  static const _newConflictFeedback = ExternalImportFeedback.info(
    '기존 책이 새로 확인되어 선택에서 제외했어요. 목록을 확인해 주세요.',
  );

  /// 서버를 쓰지 않는 경우(동기화 꺼짐·계정 없음)의 가져오기. 로컬 DB에
  /// 한 트랜잭션으로 저장하므로 사전 동기화나 복구 메모 정리가 필요 없다.
  /// 예외는 [startImport]의 공통 처리로 넘긴다.
  Future<ExternalImportFeedback?> _importLocally(
    ExternalImportParseResult input,
    int ownerUserId,
    int generation,
  ) async {
    state = state.copyWith(
      phase: ExternalImportPhase.importing,
      clearMessage: true,
      needsRefresh: false,
    );
    developer.log(
      '[외부 기록 가져오기 시작] userId=$ownerUserId '
      'source=${input.source.code} selectedBookCount=${state.selectedBookCount} '
      'overwriteCount=${state.overwriteBookIndexes.length} '
      'mode=LOCAL result=SUCCESS',
    );
    final existingBooksByIsbn = await _loadExistingBooks(input);
    _checkSession(ownerUserId, generation);
    final selection = _confirmSelection(input, existingBooksByIsbn);
    if (selection == null) return _newConflictFeedback;

    await ref
        .read(externalRecordLocalImportServiceProvider)
        .run(
          selection.input,
          ownerUserId: ownerUserId,
          sessionValid: () =>
              generation == BookshelfDatabase.sessionGeneration &&
              ref.read(recordOwnerIdProvider) == ownerUserId,
          existingBooksByIsbn: existingBooksByIsbn,
          overwriteExistingIsbns: selection.overwriteExistingIsbns,
        );
    _completeImport(
      selectedBookCount: selection.input.books.length,
      needsRefresh: false,
    );
    developer.log(
      '[외부 기록 가져오기 흐름] userId=$ownerUserId '
      'source=${input.source.code} stage=completed mode=LOCAL '
      'selectedBookCount=${selection.input.books.length} result=SUCCESS',
    );
    return null;
  }

  /// 저장 직전 기존 책을 다시 확인한다. 목록에서 명시적으로 덮어쓰기를
  /// 고르지 않은 충돌이 새로 생겼으면 선택에서 빼고 null을 반환해, 분석
  /// 이후 생긴 변경을 조용히 덮지 않는다.
  ({ExternalImportParseResult input, Set<String> overwriteExistingIsbns})?
  _confirmSelection(
    ExternalImportParseResult input,
    Map<String, BookItem> existingBooksByIsbn,
  ) {
    final currentConflicts = _conflictingIndexes(input, existingBooksByIsbn);
    final selectedIndexes = state.selectedBookIndexes.toSet();
    final overwriteIndexes = state.overwriteBookIndexes.toSet();
    final newlyProtected = selectedIndexes.where(
      (index) =>
          currentConflicts.contains(index) && !overwriteIndexes.contains(index),
    );
    if (newlyProtected.isNotEmpty) {
      selectedIndexes.removeAll(newlyProtected);
      if (!_disposed) {
        state = state.copyWith(
          phase: ExternalImportPhase.ready,
          selectedBookIndexes: Set.unmodifiable(selectedIndexes),
          conflictingBookIndexes: Set.unmodifiable(currentConflicts),
          overwriteBookIndexes: Set.unmodifiable(
            overwriteIndexes.intersection(currentConflicts),
          ),
        );
      }
      return null;
    }
    return (
      input: ExternalImportParseResult(
        source: input.source,
        books: selectedIndexes
            .map((index) => input.books[index])
            .toList(growable: false),
        discoveredBookCount: input.discoveredBookCount,
        skippedItemCount: input.skippedItemCount,
        warningCount: input.warningCount,
      ),
      overwriteExistingIsbns: overwriteIndexes
          .map((index) => input.books[index].isbn13)
          .whereType<String>()
          .toSet(),
    );
  }

  void _completeImport({
    required int selectedBookCount,
    required bool needsRefresh,
  }) {
    if (_disposed) return;
    ref.read(bookshelfSyncVersionProvider.notifier).state++;
    ref.read(bookNoteSyncVersionProvider.notifier).state++;
    ref.read(bookReflectionSyncVersionProvider.notifier).state++;
    ref.read(tagSyncVersionProvider.notifier).state++;
    state = state.copyWith(
      phase: ExternalImportPhase.completed,
      message: needsRefresh
          ? '기록은 가져왔지만 목록 새로고침이 필요해요.'
          : '$selectedBookCount권의 기록을 가져왔어요.',
      needsRefresh: needsRefresh,
    );
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

  Set<int> _conflictingIndexes(
    ExternalImportParseResult input,
    Map<String, BookItem> existingBooksByIsbn,
  ) {
    return {
      for (var index = 0; index < input.books.length; index++)
        if (input.books[index].isbn13 case final isbn13?
            when existingBooksByIsbn.containsKey(isbn13))
          index,
    };
  }

  Future<({int deletedNoteCount, int deletedMemoCount})>
  _removeRestoredBookMemos({
    required int ownerUserId,
    required ExternalRecordImportResult result,
  }) async {
    if (result.restoredBooksByIsbn.isEmpty) {
      return (deletedNoteCount: 0, deletedMemoCount: 0);
    }

    final bookshelfRepository = ref.read(bookshelfRepositoryProvider);
    final noteRepository = ref.read(bookNoteRepositoryProvider);
    var deletedNoteCount = 0;
    var deletedMemoCount = 0;
    for (final restored in result.restoredBooksByIsbn.entries) {
      final book = await bookshelfRepository.getByIsbn13(restored.key);
      final effectiveServerId = book?.serverId ?? book?.userBookId;
      if (book == null || effectiveServerId != restored.value.bookServerId) {
        continue;
      }

      final summaries = await noteRepository.findByUserBook(
        ownerUserId: ownerUserId,
        userBookId: book.userBookId,
      );
      final detailsByNoteLocalId = <int, BookNoteDetail>{};
      for (final summary in summaries) {
        final note = summary.note;
        final serverNoteId = note.serverId;
        if (serverNoteId == null ||
            !restored.value.importedNoteServerIds.contains(serverNoteId)) {
          continue;
        }
        final detail = await noteRepository.findDetail(
          ownerUserId: ownerUserId,
          userBookId: book.userBookId,
          noteId: note.id,
        );
        if (detail != null) detailsByNoteLocalId[note.id] = detail;
      }
      final plan = buildRestoredBookMemoCleanupPlan(
        imported: restored.value,
        summaries: summaries,
        detailsByNoteLocalId: detailsByNoteLocalId,
      );
      if (plan == null) {
        developer.log(
          '[외부 기록 복구 메모 정리] bookId=${book.userBookId} '
          'result=SKIP reason=imported_mapping_not_confirmed',
        );
        continue;
      }
      for (final noteLocalId in plan.noteLocalIds) {
        await noteRepository.deleteNote(
          ownerUserId: ownerUserId,
          userBookId: book.userBookId,
          noteId: noteLocalId,
        );
        deletedNoteCount++;
      }
      for (final target in plan.memoTargets) {
        await noteRepository.deleteNoteMemo(
          ownerUserId: ownerUserId,
          userBookId: book.userBookId,
          noteId: target.noteLocalId,
          noteMemoId: target.memoLocalId,
          previousLocalImagePath: target.previousLocalImagePath,
        );
        deletedMemoCount++;
      }
    }
    developer.log(
      '[외부 기록 복구 메모 정리] '
      'restoredBookCount=${result.restoredBooksByIsbn.length} '
      'deletedNoteCount=$deletedNoteCount '
      'deletedMemoCount=$deletedMemoCount result=SUCCESS',
    );
    return (
      deletedNoteCount: deletedNoteCount,
      deletedMemoCount: deletedMemoCount,
    );
  }

  void _checkSession(int ownerUserId, int generation) {
    if (generation != BookshelfDatabase.sessionGeneration ||
        ref.read(recordOwnerIdProvider) != ownerUserId) {
      throw const _ExternalImportSessionChanged();
    }
  }

  bool _allSyncsHealthy() {
    return !ref.read(bookshelfSyncControllerProvider).hasError &&
        !ref.read(bookNoteSyncControllerProvider).hasError &&
        !ref.read(bookReflectionSyncControllerProvider).hasError &&
        !ref.read(tagSyncControllerProvider).hasError;
  }

  bool _bookAndNoteSyncsHealthy() {
    return !ref.read(bookshelfSyncControllerProvider).hasError &&
        !ref.read(bookNoteSyncControllerProvider).hasError;
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
