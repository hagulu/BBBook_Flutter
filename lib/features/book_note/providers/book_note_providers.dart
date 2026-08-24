import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_notifier.dart';
import '../../auth/providers/auth_providers.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../record_sync/providers/record_sync_providers.dart';
import '../data/book_note_api.dart';
import '../data/book_note_dao.dart';
import '../data/book_note_repository.dart';
import '../models/book_note.dart';

final bookNoteDaoProvider = Provider<BookNoteDao>((ref) {
  return const BookNoteDao();
});

final bookNoteApiProvider = Provider<BookNoteApi>((ref) {
  return BookNoteApi(apiClient: ref.watch(apiClientProvider));
});

final bookNoteRepositoryProvider = Provider<BookNoteRepository>((ref) {
  return BookNoteRepository(
    api: ref.watch(bookNoteApiProvider),
    // 최초 기록 전체 조회(`/api/me/records`)를 노트 전체 동기화에도 그대로
    // 재사용한다(record_sync 기능이 이미 그 API를 감싸고 있다).
    recordSyncApi: ref.watch(recordSyncApiProvider),
    bookshelfRepository: ref.watch(bookshelfRepositoryProvider),
    dao: ref.watch(bookNoteDaoProvider),
  );
});

/// 동기화로 로컬 DB가 실제로 바뀌었을 때만 값을 올려 노트 목록 Provider를
/// 무효화한다(변경 없는 증분 동기화는 재조회를 생략) —
/// `bookshelfSyncVersionProvider`와 같은 역할.
final bookNoteSyncVersionProvider = StateProvider<int>((ref) => 0);

/// 노트 동기화 실행/상태 관리(최초엔 전체 동기화, 이후엔 증분 동기화).
/// `/api/me/notes/sync/changes`는 책 단위가 아닌 계정 전체를 대상으로 하므로
/// 이 컨트롤러도 책 하나에 매이지 않는 전역 상태다 —
/// `BookshelfSyncController`와 같은 구조.
class BookNoteSyncController extends AsyncNotifier<DateTime?> {
  late BookNoteRepository _repository;
  Future<void>? _inFlight;
  bool _disposed = false;

  @override
  FutureOr<DateTime?> build() async {
    ref.onDispose(() => _disposed = true);
    _repository = ref.watch(bookNoteRepositoryProvider);
    return _repository.getLastSyncedAtNote();
  }

  /// 당겨서 새로고침 등 겹쳐 호출돼도 진행 중인 동기화 Future를 그대로
  /// 공유해, 중복 네트워크 요청과 상태 덮어쓰기를 막는다.
  Future<void> syncNow() {
    return _inFlight ??= _runSync().whenComplete(() => _inFlight = null);
  }

  Future<void> _runSync() async {
    final ownerUserId = ref.read(
      authNotifierProvider.select((auth) => auth.user?.id),
    );
    if (ownerUserId == null) return;

    state = const AsyncValue<DateTime?>.loading().copyWithPrevious(state);
    try {
      final changed = await _repository.sync(ownerUserId: ownerUserId);
      final syncedAt = await _repository.getLastSyncedAtNote();
      if (_disposed) return;
      state = AsyncValue.data(syncedAt);
      if (changed) {
        ref.read(bookNoteSyncVersionProvider.notifier).state++;
      }
    } catch (e, st) {
      if (_disposed) return;
      state = AsyncValue<DateTime?>.error(e, st).copyWithPrevious(state);
    }
  }
}

final bookNoteSyncControllerProvider =
    AsyncNotifierProvider<BookNoteSyncController, DateTime?>(
      BookNoteSyncController.new,
    );

final bookNoteListProvider = FutureProvider.autoDispose
    .family<List<BookNoteSummary>, int>((ref, userBookId) async {
      final ownerUserId = ref.watch(
        authNotifierProvider.select((auth) => auth.user?.id),
      );
      if (ownerUserId == null) return const [];
      ref.watch(bookNoteSyncVersionProvider);
      return ref
          .watch(bookNoteRepositoryProvider)
          .findByUserBook(ownerUserId: ownerUserId, userBookId: userBookId);
    });

class BookNoteDetailArgs {
  const BookNoteDetailArgs({
    required this.ownerUserId,
    required this.userBookId,
    required this.noteId,
  });

  final int ownerUserId;
  final int userBookId;
  final int? noteId;

  @override
  bool operator ==(Object other) {
    return other is BookNoteDetailArgs &&
        other.ownerUserId == ownerUserId &&
        other.userBookId == userBookId &&
        other.noteId == noteId;
  }

  @override
  int get hashCode => Object.hash(ownerUserId, userBookId, noteId);
}

class BookNoteDetailController
    extends AutoDisposeFamilyAsyncNotifier<BookNoteDetail, BookNoteDetailArgs> {
  late BookNoteRepository _repository;
  int? _noteId;
  bool _disposed = false;

  @override
  FutureOr<BookNoteDetail> build(BookNoteDetailArgs args) async {
    // 재빌드마다 새로 등록한다 — 화면을 벗어난(또는 다시 만들어진) 뒤
    // 늦게 끝난 사진 다운로드가 state를 건드리지 않게 하기 위한 표시다.
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.watch(bookNoteSyncVersionProvider);
    final currentUserId = ref.watch(
      authNotifierProvider.select((auth) => auth.user?.id),
    );
    if (currentUserId != args.ownerUserId) {
      return const BookNoteDetail.empty();
    }
    _repository = ref.watch(bookNoteRepositoryProvider);
    _noteId = args.noteId;
    if (_noteId == null) return const BookNoteDetail.empty();
    final detail =
        await _repository.findDetail(
          ownerUserId: args.ownerUserId,
          userBookId: args.userBookId,
          noteId: _noteId!,
        ) ??
        const BookNoteDetail.empty();
    // 이 노트의 사진만 지금 확보한다(전체 일괄 다운로드는 하지 않는다).
    // 새로 받은 사진이 있으면 로컬 경로가 채워진 최신 상태로 다시 읽는다.
    unawaited(_ensureImages(args));
    return detail;
  }

  /// 사진 다운로드는 화면 표시를 막지 않는다 — 받는 동안에는 서버 URL로
  /// 보이고, 다 받으면 로컬 경로가 반영된 상태로 다시 그린다.
  Future<void> _ensureImages(BookNoteDetailArgs args) async {
    final noteId = _noteId;
    if (noteId == null) return;
    final downloaded = await _repository.ensureImagesForNote(noteId);
    if (!downloaded || _disposed) return;
    final refreshed = await _repository.findDetail(
      ownerUserId: args.ownerUserId,
      userBookId: args.userBookId,
      noteId: noteId,
    );
    if (refreshed == null || _disposed) return;
    state = AsyncValue.data(refreshed);
  }

  Future<BookNote> saveTitle(String? title) async {
    final normalized = title?.trim();
    final savedTitle = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    final current = state.value ?? const BookNoteDetail.empty();
    if (current.note != null && current.note!.title == savedTitle) {
      return current.note!;
    }

    final note = await _repository.saveTitle(
      ownerUserId: arg.ownerUserId,
      userBookId: arg.userBookId,
      noteId: _noteId,
      title: savedTitle,
    );
    _noteId = note.id;
    state = AsyncValue.data(current.copyWith(note: note));
    return note;
  }

  Future<void> createNoteMemo(BookNoteMemoDraft draft) async {
    final noteId = _noteId;
    if (noteId == null) throw StateError('Note title must be saved first');
    final memo = await _repository.createNoteMemo(
      ownerUserId: arg.ownerUserId,
      userBookId: arg.userBookId,
      noteId: noteId,
      draft: draft,
    );
    final current = state.value ?? const BookNoteDetail.empty();
    state = AsyncValue.data(current.copyWith(memos: [...current.memos, memo]));
  }

  Future<void> updateNoteMemo(int noteMemoId, BookNoteMemoDraft draft) async {
    final noteId = _noteId;
    if (noteId == null) throw StateError('Note not found');
    final beforeSave = state.value ?? const BookNoteDetail.empty();
    final previousMemo = _requireMemo(beforeSave, noteMemoId);
    final memo = await _repository.updateNoteMemo(
      ownerUserId: arg.ownerUserId,
      userBookId: arg.userBookId,
      noteId: noteId,
      noteMemoId: noteMemoId,
      draft: draft,
      previousLocalImagePath: previousMemo.localImagePath,
    );
    final current = state.value ?? beforeSave;
    state = AsyncValue.data(
      current.copyWith(
        memos: [
          for (final currentMemo in current.memos)
            if (currentMemo.id == noteMemoId) memo else currentMemo,
        ],
      ),
    );
  }

  Future<bool> deleteNoteMemo(int noteMemoId) async {
    final noteId = _noteId;
    if (noteId == null) throw StateError('Note not found');
    final beforeDelete = state.value ?? const BookNoteDetail.empty();
    final previousMemo = _requireMemo(beforeDelete, noteMemoId);
    final result = await _repository.deleteNoteMemo(
      ownerUserId: arg.ownerUserId,
      userBookId: arg.userBookId,
      noteId: noteId,
      noteMemoId: noteMemoId,
      previousLocalImagePath: previousMemo.localImagePath,
    );
    if (result.noteWasDeleted) {
      state = const AsyncValue.data(BookNoteDetail.empty());
      return true;
    }
    final current = state.value ?? beforeDelete;
    state = AsyncValue.data(
      current.copyWith(
        memos: current.memos
            .where((memo) => memo.id != noteMemoId)
            .toList(growable: false),
      ),
    );
    return false;
  }

  Future<void> deleteNote() async {
    final noteId = _noteId;
    if (noteId == null) throw StateError('Note not found');
    await _repository.deleteNote(
      ownerUserId: arg.ownerUserId,
      userBookId: arg.userBookId,
      noteId: noteId,
    );
    state = const AsyncValue.data(BookNoteDetail.empty());
  }

  BookNoteMemo _requireMemo(BookNoteDetail detail, int noteMemoId) {
    for (final memo in detail.memos) {
      if (memo.id == noteMemoId) return memo;
    }
    throw StateError('Note memo not found');
  }
}

final bookNoteDetailProvider = AsyncNotifierProvider.autoDispose
    .family<BookNoteDetailController, BookNoteDetail, BookNoteDetailArgs>(
      BookNoteDetailController.new,
    );
