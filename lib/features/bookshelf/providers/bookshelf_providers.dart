import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/bookshelf_api.dart';
import '../data/bookshelf_repository.dart';
import '../models/book_item.dart';
import '../models/book_status.dart';
import '../models/book_tag.dart';
import '../models/finished_filter.dart';

final bookshelfApiProvider = Provider<BookshelfApi>((ref) {
  return BookshelfApi(apiClient: ref.watch(apiClientProvider));
});

final bookshelfRepositoryProvider = Provider<BookshelfRepository>((ref) {
  return BookshelfRepository(api: ref.watch(bookshelfApiProvider));
});

/// 동기화로 로컬 DB가 실제로 바뀌었을 때만 값을 올려 탭별 목록 Provider들을
/// 무효화한다(변경 없는 증분 동기화는 재조회를 생략). 책 기록 화면의 자체
/// 저장도 이 값을 올려 책장 탭을 갱신한다(둘 다 "책장 목록이 바뀜"이라는
/// 같은 의미이므로 공유해도 된다).
final bookshelfSyncVersionProvider = StateProvider<int>((ref) => 0);

/// [BookshelfSyncController]의 실제 동기화(당겨서 새로고침, 포그라운드 전환
/// 등)가 로컬 DB를 바꿨을 때만 올라간다. `bookshelfSyncVersionProvider`와
/// 달리 책 기록 화면 자신의 저장으로는 절대 올라가지 않는다 — 상세 화면이
/// "다른 곳에서 이 책이 바뀌었는지"만 구분해서 구독하기 위한 신호다. 같이
/// 묶으면 자기 저장 직후에도 상세 컨트롤러가 다시 빌드되며 로딩 오버레이가
/// 불필요하게 깜빡인다.
final externalSyncVersionProvider = StateProvider<int>((ref) => 0);

/// 동기화 실행/상태 관리(최초엔 전체 동기화, 이후엔 증분 동기화). 값은
/// 마지막 동기화 시각(없으면 null).
class BookshelfSyncController extends AsyncNotifier<DateTime?> {
  late BookshelfRepository _repository;
  Future<void>? _inFlight;
  bool _disposed = false;

  @override
  FutureOr<DateTime?> build() async {
    ref.onDispose(() => _disposed = true);
    _repository = ref.watch(bookshelfRepositoryProvider);
    return _repository.getLastSyncedAt();
  }

  /// 포그라운드 전환·Pull to Refresh가 겹쳐 호출돼도 진행 중인 동기화
  /// Future를 그대로 공유해, 중복 네트워크 요청과 상태 덮어쓰기를 막는다.
  Future<void> syncNow() {
    return _inFlight ??= _runSync().whenComplete(() => _inFlight = null);
  }

  Future<void> _runSync() async {
    // 이전 값(마지막 동기화 시각)을 유지한 채 loading으로 전환한다. 화면이
    // valueOrNull로 "최초 동기화 여부"를 판단하므로(BookshelfScreen), 여기서
    // 값을 날리면 이미 데이터가 있는데도 매 갱신마다 최초 동기화로 오인해
    // 전체 화면 로딩/에러로 덮어써 버린다.
    state = const AsyncValue<DateTime?>.loading().copyWithPrevious(state);
    try {
      final changed = await _repository.sync();
      final syncedAt = await _repository.getLastSyncedAt();
      // 로그아웃(ref.invalidate)이 await 도중 이 notifier를 폐기했을 수 있다.
      // 폐기된 notifier에 state를 쓰면 예외가 나므로, 그 결과는 버린다 —
      // 어차피 이 provider는 다시 로그인할 때 build()부터 새로 시작한다.
      if (_disposed) return;
      state = AsyncValue.data(syncedAt);
      if (changed) {
        ref.read(bookshelfSyncVersionProvider.notifier).state++;
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
    final lastSynced = state.valueOrNull ?? await _repository.getLastSyncedAt();
    if (lastSynced == null ||
        DateTime.now().difference(lastSynced) > throttle) {
      await syncNow();
    }
  }
}

final bookshelfSyncControllerProvider =
    AsyncNotifierProvider<BookshelfSyncController, DateTime?>(
      BookshelfSyncController.new,
    );

final readingTabProvider = FutureProvider<List<BookItem>>((ref) {
  ref.watch(bookshelfSyncVersionProvider);
  return ref.watch(bookshelfRepositoryProvider).getReadingTab();
});

final gridTabProvider = FutureProvider.family<List<BookItem>, BookStatus>((
  ref,
  status,
) {
  ref.watch(bookshelfSyncVersionProvider);
  return ref.watch(bookshelfRepositoryProvider).getGridTab(status);
});

/// 완독 탭 검색/필터 상태.
class FinishedFilterNotifier extends Notifier<FinishedFilter> {
  @override
  FinishedFilter build() => const FinishedFilter();

  void setKeyword(String keyword) => state = state.copyWith(keyword: keyword);

  void setCategory(String? category) {
    state = state.copyWith(category: category, clearCategory: category == null);
  }

  void toggleTag(int tagId) {
    final tags = Set<int>.from(state.tagIds);
    if (!tags.remove(tagId)) {
      tags.add(tagId);
    }
    state = state.copyWith(tagIds: tags);
  }

  void setMasterpieceOnly(bool value) =>
      state = state.copyWith(masterpieceOnly: value);

  void setDifficulty(String? difficulty) {
    state = state.copyWith(
      difficulty: difficulty,
      clearDifficulty: difficulty == null,
    );
  }

  void reset() => state = const FinishedFilter();
}

final finishedFilterProvider =
    NotifierProvider<FinishedFilterNotifier, FinishedFilter>(
      FinishedFilterNotifier.new,
    );

final finishedBooksProvider = FutureProvider<List<BookItem>>((ref) {
  ref.watch(bookshelfSyncVersionProvider);
  final filter = ref.watch(finishedFilterProvider);
  return ref.watch(bookshelfRepositoryProvider).searchFinished(filter);
});

final finishedCategoryOptionsProvider = FutureProvider<List<String>>((ref) {
  ref.watch(bookshelfSyncVersionProvider);
  return ref.watch(bookshelfRepositoryProvider).getDistinctCategories();
});

final finishedTagOptionsProvider = FutureProvider<List<BookTag>>((ref) {
  ref.watch(bookshelfSyncVersionProvider);
  return ref.watch(bookshelfRepositoryProvider).getDistinctTags();
});

final finishedDifficultyOptionsProvider = FutureProvider<List<String>>((ref) {
  ref.watch(bookshelfSyncVersionProvider);
  return ref.watch(bookshelfRepositoryProvider).getDistinctDifficulties();
});

/// 완독 책장 공개 여부(지구본/자물쇠 토글). 완독 탭 진입 시 조회한다.
class PrivacySettingController extends AsyncNotifier<bool> {
  late BookshelfRepository _repository;

  @override
  FutureOr<bool> build() async {
    _repository = ref.watch(bookshelfRepositoryProvider);
    return _repository.getPrivacySetting();
  }

  Future<void> toggle(bool isFinishedBooksPublic) async {
    final previous = state.valueOrNull ?? false;
    state = const AsyncValue.loading();
    try {
      final result = await _repository.setPrivacySetting(isFinishedBooksPublic);
      state = AsyncValue.data(result);
    } catch (e, st) {
      state = AsyncValue.data(previous);
      Error.throwWithStackTrace(e, st);
    }
  }
}

final privacySettingControllerProvider =
    AsyncNotifierProvider<PrivacySettingController, bool>(
      PrivacySettingController.new,
    );
