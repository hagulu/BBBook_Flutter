import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_notifier.dart';
import '../data/book_memo_dao.dart';
import '../data/book_memo_repository.dart';
import '../models/book_memo.dart';

final bookMemoDaoProvider = Provider<BookMemoDao>((ref) {
  return const BookMemoDao();
});

final bookMemoRepositoryProvider = Provider<BookMemoRepository>((ref) {
  return BookMemoRepository(ref.watch(bookMemoDaoProvider));
});

final bookMemoListProvider = FutureProvider.autoDispose
    .family<List<BookMemoSummary>, int>((ref, userBookId) async {
      final ownerUserId = ref.watch(
        authNotifierProvider.select((auth) => auth.user?.id),
      );
      if (ownerUserId == null) return const [];
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
    state = AsyncValue.data(current.copyWith(items: [item, ...current.items]));
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
