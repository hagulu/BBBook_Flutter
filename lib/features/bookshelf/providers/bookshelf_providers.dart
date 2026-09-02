import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../book_detail/data/book_detail_api.dart';
import '../../book_record/data/book_record_api.dart';
import '../../book_search/data/book_search_api.dart';
import '../data/bookshelf_api.dart';
import '../data/bookshelf_repository.dart';
import '../models/book_category.dart';
import '../models/book_item.dart';
import '../models/book_status.dart';
import '../models/book_tag.dart';
import '../models/finished_filter.dart';

final bookshelfApiProvider = Provider<BookshelfApi>((ref) {
  return BookshelfApi(apiClient: ref.watch(apiClientProvider));
});

/// dirty 책 기록 push 전용으로 별도 생성한다(book_record 기능의
/// `bookRecordApiProvider`를 재사용하려면 이 파일이 book_record_providers.dart를
/// 가져와야 하는데, 그 파일이 이미 이 파일을 가져오므로 순환 참조가 된다.
/// `BookRecordApi`는 상태 없이 [ApiClient]만 감싸는 얇은 클래스라 인스턴스가
/// 둘로 나뉘어도 무해하다).
final bookshelfRepositoryProvider = Provider<BookshelfRepository>((ref) {
  return BookshelfRepository(
    api: ref.watch(bookshelfApiProvider),
    recordApi: BookRecordApi(apiClient: ref.watch(apiClientProvider)),
    bookDetailApi: BookDetailApi(apiClient: ref.watch(apiClientProvider)),
    bookSearchApi: BookSearchApi(apiClient: ref.watch(apiClientProvider)),
  );
});

/// 카테고리 마스터 목록(계정과 무관한 정적 데이터, 로컬 DB에 캐시됨).
/// `autoDispose`로 두되 성공했을 때만 `ref.keepAlive()`로 폐기를 막는다 —
/// 성공 시에는 화면을 오가도 재조회하지 않고, 실패(오프라인 등) 시에는
/// 마지막 구독자가 사라지며 폐기되어 다음에 화면을 다시 열 때 재시도된다.
final bookCategoriesProvider = FutureProvider.autoDispose<List<BookCategory>>((
  ref,
) async {
  final categories = await ref
      .watch(bookshelfRepositoryProvider)
      .getCategories();
  ref.keepAlive();
  return categories;
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

  /// 책 검색/상세에서 방금 서버에 추가한 [userBookId]가 로컬 DB에 반영될
  /// 때까지 동기화한다. [syncNow]가 이미 진행 중인 다른 동기화(포그라운드
  /// 전환의 `syncIfStale` 등)와 합류(coalescing)하면, 그 동기화의 서버 요청이
  /// 이번 추가보다 먼저 나간 것일 수 있어 새 책이 반영되지 않을 수 있다 — 그
  /// 경우 한 번 더(이번엔 새로 시작하는) 동기화를 시도한다.
  Future<bool> ensureSynced(int userBookId) async {
    await syncNow();
    if (await _repository.getById(userBookId) != null) return true;
    await syncNow();
    return await _repository.getById(userBookId) != null;
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

  void toggleCategory(String category) {
    final categories = Set<String>.from(state.categories);
    if (!categories.remove(category)) {
      categories.add(category);
    }
    state = state.copyWith(categories: categories);
  }

  void clearCategories() => state = state.copyWith(categories: const {});

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

  /// 검색을 완전히 "종료"할 때(검색 바 닫기) 쓰는 전체 초기화 — 검색어까지
  /// 함께 지운다.
  void reset() => state = const FinishedFilter();

  /// 필터 바텀시트의 "초기화" — 검색어는 필터 기준이 아니므로 그대로 두고
  /// 카테고리·태그·명작·난이도만 지운다.
  void resetCriteria() => state = FinishedFilter(keyword: state.keyword);
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

/// 완독한 책 중 ISBN(공용 book 연결)이 없는 책. 완독 상단 배너(일괄 연결
/// 진입점)용이라 사용자가 걸어둔 검색/필터([finishedFilterProvider])와는
/// 무관하게 항상 전체 완독 목록 기준으로 센다. 일괄 연결 검색 시트에서
/// "목록에서 제외"를 켠 채 건너뛴 책(`dismissed_isbn_link`)은 뺀다.
final unlinkedFinishedBooksProvider = FutureProvider<List<BookItem>>((
  ref,
) async {
  ref.watch(bookshelfSyncVersionProvider);
  final repository = ref.watch(bookshelfRepositoryProvider);
  final all = await repository.searchFinished(const FinishedFilter());
  final dismissed = await repository.getDismissedIsbnLinkUserBookIds();
  return all
      .where(
        (book) => book.isbn13 == null && !dismissed.contains(book.userBookId),
      )
      .toList();
});

final finishedCategoryOptionsProvider = FutureProvider<List<String>>((ref) {
  ref.watch(bookshelfSyncVersionProvider);
  return ref.watch(bookshelfRepositoryProvider).getDistinctCategories();
});

final finishedTagOptionsProvider = FutureProvider<List<BookTag>>((ref) {
  ref.watch(bookshelfSyncVersionProvider);
  return ref.watch(bookshelfRepositoryProvider).getDistinctTags();
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
