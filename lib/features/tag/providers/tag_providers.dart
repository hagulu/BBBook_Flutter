import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../record_sync/providers/record_sync_providers.dart';
import '../data/tag_api.dart';
import '../data/tag_dao.dart';
import '../data/tag_repository.dart';

final tagDaoProvider = Provider<TagDao>((ref) {
  return const TagDao();
});

final tagApiProvider = Provider<TagApi>((ref) {
  return TagApi(apiClient: ref.watch(apiClientProvider));
});

final tagRepositoryProvider = Provider<TagRepository>((ref) {
  return TagRepository(
    api: ref.watch(tagApiProvider),
    // 최초 전체 조회(`/api/me/records`)를 태그 전체 동기화에도 그대로
    // 재사용한다(record_sync 기능이 이미 그 API를 감싸고 있다).
    recordSyncApi: ref.watch(recordSyncApiProvider),
    bookshelfRepository: ref.watch(bookshelfRepositoryProvider),
    dao: ref.watch(tagDaoProvider),
  );
});

/// 동기화로 로컬 DB가 실제로 바뀌었을 때만 값을 올려 태그를 보여주는 화면을
/// 무효화한다 — `bookshelfSyncVersionProvider`와 같은 역할.
final tagSyncVersionProvider = StateProvider<int>((ref) => 0);

/// 태그 동기화 실행/상태 관리(최초엔 전체 동기화, 이후엔 증분 동기화).
/// 태그/매핑은 책 하나에 매이지 않는 계정 전체 단위라 `BookshelfSyncController`와
/// 같은(책별 owner 없는) 구조다.
class TagSyncController extends AsyncNotifier<DateTime?> {
  late TagRepository _repository;
  Future<void>? _inFlight;
  bool _disposed = false;

  @override
  FutureOr<DateTime?> build() async {
    ref.onDispose(() => _disposed = true);
    _repository = ref.watch(tagRepositoryProvider);
    return _repository.getLastSyncedAtTag();
  }

  /// 포그라운드 전환·Pull to Refresh가 겹쳐 호출돼도 진행 중인 동기화
  /// Future를 그대로 공유해, 중복 네트워크 요청과 상태 덮어쓰기를 막는다.
  Future<void> syncNow() {
    return _inFlight ??= _runSync().whenComplete(() => _inFlight = null);
  }

  Future<void> _runSync() async {
    state = const AsyncValue<DateTime?>.loading().copyWithPrevious(state);
    try {
      final changed = await _repository.sync();
      final syncedAt = await _repository.getLastSyncedAtTag();
      if (_disposed) return;
      state = AsyncValue.data(syncedAt);
      if (changed) {
        ref.read(tagSyncVersionProvider.notifier).state++;
        // 책장 목록/완독 필터·태그 옵션(`readingTabProvider`,
        // `gridTabProvider`, `finishedTagOptionsProvider` 등)은 태그를
        // `tag`/`user_book_tag_map` 조인으로 읽으면서도 `tagSyncVersionProvider`가
        // 아니라 `bookshelfSyncVersionProvider`만 구독한다 — 그 provider들을
        // 전부 이 provider로 갈아 끼우는 대신, 책장 자체 변경 때와 같은
        // 신호를 태그 변경 때도 함께 올려 다시 읽게 한다.
        ref.read(bookshelfSyncVersionProvider.notifier).state++;
        // 다른 기기에서 바뀐 태그가 책 기록 상세 화면(BookRecordController)에
        // 즉시 반영되도록 같은 신호를 함께 올린다.
        ref.read(externalSyncVersionProvider.notifier).state++;
      }
    } catch (e, st) {
      if (_disposed) return;
      state = AsyncValue<DateTime?>.error(e, st).copyWithPrevious(state);
    }
  }

  /// 마지막 동기화가 [throttle]보다 오래됐을 때만 동기화한다(앱 포그라운드 전환용).
  Future<void> syncIfStale({
    Duration throttle = const Duration(minutes: 10),
  }) async {
    final lastSynced = state.valueOrNull ?? await _repository.getLastSyncedAtTag();
    if (lastSynced == null ||
        DateTime.now().difference(lastSynced) > throttle) {
      await syncNow();
    }
  }
}

final tagSyncControllerProvider =
    AsyncNotifierProvider<TagSyncController, DateTime?>(TagSyncController.new);
