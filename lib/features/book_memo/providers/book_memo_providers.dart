import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_notifier.dart';
import '../../auth/providers/auth_providers.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../record_sync/providers/record_sync_providers.dart';
import '../data/book_memo_api.dart';
import '../data/book_memo_dao.dart';
import '../data/book_memo_repository.dart';
import '../models/book_memo.dart';

final bookMemoDaoProvider = Provider<BookMemoDao>((ref) {
  return const BookMemoDao();
});

final bookMemoApiProvider = Provider<BookMemoApi>((ref) {
  return BookMemoApi(apiClient: ref.watch(apiClientProvider));
});

final bookMemoRepositoryProvider = Provider<BookMemoRepository>((ref) {
  return BookMemoRepository(
    api: ref.watch(bookMemoApiProvider),
    // 최초 기록 전체 조회(`/api/me/records`)를 메모 전체 동기화에도 그대로
    // 재사용한다(record_sync 기능이 이미 그 API를 감싸고 있다).
    recordSyncApi: ref.watch(recordSyncApiProvider),
    bookshelfRepository: ref.watch(bookshelfRepositoryProvider),
    dao: ref.watch(bookMemoDaoProvider),
  );
});

/// 동기화로 로컬 DB가 실제로 바뀌었을 때만 값을 올려 메모 목록 Provider를
/// 무효화한다(변경 없는 증분 동기화는 재조회를 생략) —
/// `bookshelfSyncVersionProvider`와 같은 역할.
final bookMemoSyncVersionProvider = StateProvider<int>((ref) => 0);

/// 메모 동기화 실행/상태 관리(최초엔 전체 동기화, 이후엔 증분 동기화).
/// `/api/me/memos/sync/changes`는 책 단위가 아닌 계정 전체를 대상으로 하므로
/// 이 컨트롤러도 책 하나에 매이지 않는 전역 상태다 —
/// `BookshelfSyncController`와 같은 구조.
class BookMemoSyncController extends AsyncNotifier<DateTime?> {
  late BookMemoRepository _repository;
  Future<void>? _inFlight;
  bool _disposed = false;

  @override
  FutureOr<DateTime?> build() async {
    ref.onDispose(() => _disposed = true);
    _repository = ref.watch(bookMemoRepositoryProvider);
    return _repository.getLastSyncedAtMemo();
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
      final syncedAt = await _repository.getLastSyncedAtMemo();
      if (_disposed) return;
      state = AsyncValue.data(syncedAt);
      if (changed) {
        ref.read(bookMemoSyncVersionProvider.notifier).state++;
      }
    } catch (e, st) {
      if (_disposed) return;
      state = AsyncValue<DateTime?>.error(e, st).copyWithPrevious(state);
    }
  }
}

final bookMemoSyncControllerProvider =
    AsyncNotifierProvider<BookMemoSyncController, DateTime?>(
      BookMemoSyncController.new,
    );

final bookMemoListProvider = FutureProvider.autoDispose
    .family<List<BookMemoSummary>, int>((ref, userBookId) async {
      final ownerUserId = ref.watch(
        authNotifierProvider.select((auth) => auth.user?.id),
      );
      if (ownerUserId == null) return const [];
      ref.watch(bookMemoSyncVersionProvider);
      return ref
          .watch(bookMemoRepositoryProvider)
          .findByUserBook(ownerUserId: ownerUserId, userBookId: userBookId);
    });

class BookMemoDetailArgs {
  const BookMemoDetailArgs({
    required this.ownerUserId,
    required this.userBookId,
    required this.memoId,
  });

  final int ownerUserId;
  final int userBookId;
  final int? memoId;

  @override
  bool operator ==(Object other) {
    return other is BookMemoDetailArgs &&
        other.ownerUserId == ownerUserId &&
        other.userBookId == userBookId &&
        other.memoId == memoId;
  }

  @override
  int get hashCode => Object.hash(ownerUserId, userBookId, memoId);
}

class BookMemoDetailController
    extends AutoDisposeFamilyAsyncNotifier<BookMemoDetail, BookMemoDetailArgs> {
  late BookMemoRepository _repository;
  int? _memoId;

  @override
  FutureOr<BookMemoDetail> build(BookMemoDetailArgs args) async {
    ref.watch(bookMemoSyncVersionProvider);
    final currentUserId = ref.watch(
      authNotifierProvider.select((auth) => auth.user?.id),
    );
    if (currentUserId != args.ownerUserId) {
      return const BookMemoDetail.empty();
    }
    _repository = ref.watch(bookMemoRepositoryProvider);
    _memoId = args.memoId;
    if (_memoId == null) return const BookMemoDetail.empty();
    return await _repository.findDetail(
          ownerUserId: args.ownerUserId,
          userBookId: args.userBookId,
          memoId: _memoId!,
        ) ??
        const BookMemoDetail.empty();
  }

  Future<BookMemo> saveTitle(String? title) async {
    final normalized = title?.trim();
    final savedTitle = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    final current = state.value ?? const BookMemoDetail.empty();
    if (current.memo != null && current.memo!.title == savedTitle) {
      return current.memo!;
    }

    final memo = await _repository.saveTitle(
      ownerUserId: arg.ownerUserId,
      userBookId: arg.userBookId,
      memoId: _memoId,
      title: savedTitle,
    );
    _memoId = memo.id;
    state = AsyncValue.data(current.copyWith(memo: memo));
    return memo;
  }

  Future<void> createItem(BookMemoItemDraft draft) async {
    final memoId = _memoId;
    if (memoId == null) throw StateError('Memo title must be saved first');
    final item = await _repository.createItem(
      ownerUserId: arg.ownerUserId,
      userBookId: arg.userBookId,
      memoId: memoId,
      draft: draft,
    );
    final current = state.value ?? const BookMemoDetail.empty();
    state = AsyncValue.data(current.copyWith(items: [...current.items, item]));
  }

  Future<void> updateItem(int itemId, BookMemoItemDraft draft) async {
    final memoId = _memoId;
    if (memoId == null) throw StateError('Memo not found');
    final beforeSave = state.value ?? const BookMemoDetail.empty();
    final previousItem = _requireItem(beforeSave, itemId);
    final item = await _repository.updateItem(
      ownerUserId: arg.ownerUserId,
      userBookId: arg.userBookId,
      memoId: memoId,
      itemId: itemId,
      draft: draft,
      previousImageUrl: previousItem.imageUrl,
    );
    final current = state.value ?? beforeSave;
    state = AsyncValue.data(
      current.copyWith(
        items: [
          for (final currentItem in current.items)
            if (currentItem.id == itemId) item else currentItem,
        ],
      ),
    );
  }

  Future<bool> deleteItem(int itemId) async {
    final memoId = _memoId;
    if (memoId == null) throw StateError('Memo not found');
    final beforeDelete = state.value ?? const BookMemoDetail.empty();
    final previousItem = _requireItem(beforeDelete, itemId);
    final result = await _repository.deleteItem(
      ownerUserId: arg.ownerUserId,
      userBookId: arg.userBookId,
      memoId: memoId,
      itemId: itemId,
      previousImageUrl: previousItem.imageUrl,
    );
    if (result.memoWasDeleted) {
      state = const AsyncValue.data(BookMemoDetail.empty());
      return true;
    }
    final current = state.value ?? beforeDelete;
    state = AsyncValue.data(
      current.copyWith(
        items: current.items
            .where((item) => item.id != itemId)
            .toList(growable: false),
      ),
    );
    return false;
  }

  BookMemoItem _requireItem(BookMemoDetail detail, int itemId) {
    for (final item in detail.items) {
      if (item.id == itemId) return item;
    }
    throw StateError('Memo item not found');
  }
}

final bookMemoDetailProvider = AsyncNotifierProvider.autoDispose
    .family<BookMemoDetailController, BookMemoDetail, BookMemoDetailArgs>(
      BookMemoDetailController.new,
    );
