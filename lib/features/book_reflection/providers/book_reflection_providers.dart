import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_notifier.dart';
import '../../auth/providers/auth_providers.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../record_sync/providers/record_sync_providers.dart';
import '../data/book_reflection_api.dart';
import '../data/book_reflection_dao.dart';
import '../data/book_reflection_repository.dart';
import '../models/book_reflection.dart';

final bookReflectionDaoProvider = Provider<BookReflectionDao>((ref) {
  return const BookReflectionDao();
});

final bookReflectionApiProvider = Provider<BookReflectionApi>((ref) {
  return BookReflectionApi(apiClient: ref.watch(apiClientProvider));
});

final bookReflectionRepositoryProvider = Provider<BookReflectionRepository>((
  ref,
) {
  return BookReflectionRepository(
    api: ref.watch(bookReflectionApiProvider),
    // 최초 기록 전체 조회(`/api/me/records`)를 독후감 전체 동기화에도
    // 그대로 재사용한다(record_sync 기능이 이미 그 API를 감싸고 있다).
    recordSyncApi: ref.watch(recordSyncApiProvider),
    bookshelfRepository: ref.watch(bookshelfRepositoryProvider),
    dao: ref.watch(bookReflectionDaoProvider),
  );
});

/// 동기화로 로컬 DB가 실제로 바뀌었을 때만 값을 올려 독후감 목록/상세
/// Provider를 무효화한다(변경 없는 증분 동기화는 재조회를 생략) —
/// `bookNoteSyncVersionProvider`와 같은 역할.
final bookReflectionSyncVersionProvider = StateProvider<int>((ref) => 0);

/// 독후감 동기화 실행/상태 관리(최초엔 전체 동기화, 이후엔 증분 동기화).
/// `/api/me/reflections/sync/changes`는 책 단위가 아닌 계정 전체를
/// 대상으로 하므로 이 컨트롤러도 책 하나에 매이지 않는 전역 상태다.
class BookReflectionSyncController extends AsyncNotifier<DateTime?> {
  late BookReflectionRepository _repository;
  Future<void>? _inFlight;
  bool _disposed = false;

  @override
  FutureOr<DateTime?> build() async {
    ref.onDispose(() => _disposed = true);
    _repository = ref.watch(bookReflectionRepositoryProvider);
    return _repository.getLastSyncedAtReflection();
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
      final syncedAt = await _repository.getLastSyncedAtReflection();
      if (_disposed) return;
      state = AsyncValue.data(syncedAt);
      if (changed) {
        ref.read(bookReflectionSyncVersionProvider.notifier).state++;
      }
    } catch (e, st) {
      if (_disposed) return;
      state = AsyncValue<DateTime?>.error(e, st).copyWithPrevious(state);
    }
  }
}

final bookReflectionSyncControllerProvider =
    AsyncNotifierProvider<BookReflectionSyncController, DateTime?>(
      BookReflectionSyncController.new,
    );

final bookReflectionListProvider = FutureProvider.autoDispose
    .family<List<BookReflection>, int>((ref, userBookId) async {
      final ownerUserId = ref.watch(
        authNotifierProvider.select((auth) => auth.user?.id),
      );
      if (ownerUserId == null) return const [];
      ref.watch(bookReflectionSyncVersionProvider);
      return ref
          .watch(bookReflectionRepositoryProvider)
          .findByUserBook(ownerUserId: ownerUserId, userBookId: userBookId);
    });

class BookReflectionDetailArgs {
  const BookReflectionDetailArgs({
    required this.ownerUserId,
    required this.userBookId,
    required this.reflectionId,
  });

  final int ownerUserId;
  final int userBookId;
  final int reflectionId;

  @override
  bool operator ==(Object other) {
    return other is BookReflectionDetailArgs &&
        other.ownerUserId == ownerUserId &&
        other.userBookId == userBookId &&
        other.reflectionId == reflectionId;
  }

  @override
  int get hashCode => Object.hash(ownerUserId, userBookId, reflectionId);
}

final bookReflectionDetailProvider = FutureProvider.autoDispose
    .family<BookReflection?, BookReflectionDetailArgs>((ref, args) async {
      final currentUserId = ref.watch(
        authNotifierProvider.select((auth) => auth.user?.id),
      );
      if (currentUserId != args.ownerUserId) return null;
      ref.watch(bookReflectionSyncVersionProvider);
      return ref
          .watch(bookReflectionRepositoryProvider)
          .findDetail(
            ownerUserId: args.ownerUserId,
            userBookId: args.userBookId,
            reflectionId: args.reflectionId,
          );
    });
