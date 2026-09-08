import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../book_note/providers/book_note_providers.dart';
import '../../book_record/providers/book_record_providers.dart';
import '../../book_reflection/providers/book_reflection_providers.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
import '../../bookshelf/data/bookshelf_database.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../../tag/providers/tag_providers.dart';
import '../data/auth_api.dart' show SocialProvider;
import '../data/auth_repository.dart';
import 'auth_providers.dart';
import 'auth_state.dart';

/// 앱 전역 인증 상태를 관리한다.
///
/// - 앱 시작 시 자동으로 refresh를 시도해 세션 유지 여부를 확인한다.
/// - [ApiClient]에 토큰 조회/갱신/로그아웃 콜백을 주입해 401 발생 시
///   1회 재시도 → 실패 시 로그아웃 흐름을 공통으로 처리한다(CLAUDE.md 인증 API 호출 규칙).
/// - 실제 API/스토리지/소셜 SDK 호출은 [AuthRepository]에 위임하고, 여기서는
///   그 결과를 상태로 옮기는 역할만 한다.
class AuthNotifier extends Notifier<AuthState> {
  late final AuthRepository _repository;
  final _localReady = Completer<void>();
  Future<void>? _restoring;
  Future<String?>? _refreshing;
  Future<void>? _unauthorizing;
  DateTime? _retryAfter;
  bool _changingSession = false;
  int _generation = 0;

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);

    final apiClient = ref.watch(apiClientProvider);
    apiClient.configureAuth(
      readAccessToken: () => state.accessToken,
      refreshAccessToken: _refreshAccessToken,
      onUnauthorized: _handleUnauthorized,
      prepareSession: ensureSession,
      onUserRetry: () => _retryAfter = null,
    );

    Future.microtask(_bootstrap);

    return const AuthState();
  }

  Future<void> _bootstrap() async {
    try {
      final store = ref.read(localAuthStoreProvider);
      final user = await store.readUser();
      state = AuthState(
        status: user != null && await store.canUseRecords(user.id)
            ? AuthStatus.localOnly
            : AuthStatus.authLoading,
        user: user,
      );
    } catch (e) {
      developer.log('[로컬 세션 복원] result=FAIL reason=storage_error');
      state = const AuthState();
    } finally {
      _localReady.complete();
    }
    await recoverSession();
    if (state.isAuthLoading) {
      state = AuthState(status: AuthStatus.unauthenticated, user: state.user);
    }
  }

  /// 로컬 화면은 이 작업을 기다리지 않는다. 모든 인증 API는 이 Future를
  /// 공유해 계정 확인 이전에 기록을 다른 계정으로 전송하지 않는다.
  Future<void> ensureSession() async {
    await _localReady.future;
    if (_changingSession || state.requiresLogin) {
      throw const ApiException('같은 계정으로 다시 로그인해 주세요.');
    }
    if (_refreshing case final refreshing?) {
      final token = await refreshing;
      if (token == null) {
        await _handleUnauthorized();
        throw const ApiException('같은 계정으로 다시 로그인해 주세요.');
      }
    }
    if (_retryAfter case final retryAfter?
        when DateTime.now().isBefore(retryAfter)) {
      throw const ApiException('네트워크 연결 후 다시 시도해 주세요.');
    }
    if (state.accessToken != null) {
      if (_repository.accessTokenNeedsRefresh) {
        if (await _refreshAccessToken() == null) {
          await _handleUnauthorized();
          throw const ApiException('같은 계정으로 다시 로그인해 주세요.');
        }
      }
      return;
    }
    return _restoring ??= _restoreSession().whenComplete(
      () => _restoring = null,
    );
  }

  Future<void> recoverSession() async {
    try {
      await ensureSession();
    } catch (_) {
      developer.log('[세션 복원] result=FAIL reason=session_unavailable');
    }
  }

  Future<void> _restoreSession() async {
    final generation = _generation;
    try {
      final accessToken = await _repository.refreshAccessToken();
      if (generation != _generation) return;
      if (accessToken == null) {
        await _handleUnauthorized();
        throw const ApiException('같은 계정으로 다시 로그인해 주세요.');
      }
      final user = await _repository.fetchCurrentUser(accessToken: accessToken);
      if (generation != _generation) return;
      await _verifyLocalOwner(user.id);
      await ref.read(localAuthStoreProvider).saveUser(user);
      if (generation != _generation) return;
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        accessToken: accessToken,
      );
      _retryAfter = null;
    } on ApiException catch (e) {
      if (generation != _generation) rethrow;
      if (e.isAuthFailure || e.statusCode == 404) {
        await _handleUnauthorized();
      } else {
        _retryAfter = DateTime.now().add(const Duration(seconds: 15));
      }
      rethrow;
    } catch (_) {
      _retryAfter = DateTime.now().add(const Duration(seconds: 15));
      rethrow;
    }
  }

  Future<bool> loginWithGoogle({
    Future<bool> Function()? confirmAccountChange,
  }) =>
      _login(SocialProvider.google, confirmAccountChange: confirmAccountChange);

  Future<bool> loginWithApple({
    Future<bool> Function()? confirmAccountChange,
  }) =>
      _login(SocialProvider.apple, confirmAccountChange: confirmAccountChange);

  /// [SocialAuthException], [ApiException]은 그대로 던져 화면(SnackBar)에서 처리한다.
  Future<bool> _login(
    SocialProvider provider, {
    Future<bool> Function()? confirmAccountChange,
  }) async {
    await _localReady.future;
    if (_changingSession) return false;
    _changingSession = true;
    try {
      // 토큰 회전 중 새 로그인 토큰을 저장하는 경합을 막는다.
      try {
        await _restoring;
        await _refreshing;
      } catch (_) {}
      await _unauthorizing;
      final session = await _repository.loginWithProvider(provider);
      final localStore = ref.read(localAuthStoreProvider);
      final owner = await localStore.readUser();
      // 소유자 정보가 유실된 구형 기록도 새 로그인 계정에 임의로 합치지 않는다.
      final needsReset = owner != null
          ? owner.id != session.user.id
          : await localStore.hasLocalRecords();
      if (needsReset) {
        if (confirmAccountChange == null || !await confirmAccountChange()) {
          return false;
        }
        _generation++;
        ref.read(apiClientProvider).invalidateSession();
        await _clearLocalBookshelf();
      }
      await ref.read(localAuthStoreProvider).saveUser(session.user);
      await _repository.saveSession(session);
      _generation++;
      ref.read(apiClientProvider).invalidateSession();
      _retryAfter = null;
      state = AuthState(
        status: AuthStatus.authenticated,
        user: session.user,
        accessToken: session.accessToken,
      );
      developer.log('[소셜 로그인] provider=${provider.apiValue} result=SUCCESS');
      unawaited(_prefetchCategories());
      return true;
    } on ApiException catch (e) {
      developer.log(
        '[소셜 로그인] provider=${provider.apiValue} result=FAIL reason=${_reasonOf(e)}',
      );
      rethrow;
    } finally {
      _changingSession = false;
    }
  }

  /// null은 "저장된 refresh token 없음" 또는 "실제 인증 실패(401/403)"일 때만
  /// 반환한다. 네트워크/서버 오류 등 일시적인 실패는 [ApiException]을 그대로
  /// 던져, 호출부(ApiClient)가 이를 로그아웃과 구분해서 처리하게 한다.
  Future<String?> _refreshAccessToken() {
    if (_changingSession || state.requiresLogin) {
      return Future.error(const ApiException('로그인 상태가 변경되었습니다.'));
    }
    if (_retryAfter case final retryAfter?
        when DateTime.now().isBefore(retryAfter)) {
      return Future.error(const ApiException('네트워크 연결 후 다시 시도해 주세요.'));
    }
    if (_restoring case final restoring?) {
      return restoring.then((_) => state.accessToken);
    }
    return _refreshing ??= _runRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _runRefresh() async {
    final generation = _generation;
    try {
      final accessToken = await _repository.refreshAccessToken();
      if (generation != _generation || _changingSession) {
        throw const ApiException('로그인 상태가 변경되었습니다.');
      }
      if (accessToken != null) {
        state = AuthState(
          status: state.status,
          user: state.user,
          accessToken: accessToken,
        );
      }
      developer.log(
        '[토큰 갱신] result=${accessToken != null ? 'SUCCESS' : 'FAIL'}',
      );
      return accessToken;
    } on ApiException catch (e) {
      _retryAfter = DateTime.now().add(const Duration(seconds: 15));
      if (generation == _generation && !_changingSession) {
        state = AuthState(
          status: state.user == null
              ? AuthStatus.unauthenticated
              : AuthStatus.localOnly,
          user: state.user,
        );
      }
      developer.log(
        '[토큰 갱신] result=FAIL reason=${_reasonOf(e)} (일시 오류, 세션 유지)',
      );
      rethrow;
    }
  }

  /// 서버 로그아웃 요청이나 소셜 SDK 로그아웃이 실패해도, 상태 초기화는
  /// finally로 항상 보장한다(둘 중 하나가 막혀 로그아웃이 안 되는 상황 방지).
  Future<void> logout() async {
    _changingSession = true;
    _generation++;
    ref.read(apiClientProvider).invalidateSession();
    BookshelfDatabase.sessionGeneration++;
    try {
      try {
        await _restoring;
        await _refreshing;
      } catch (_) {}
      await _unauthorizing;
      await _repository.logout();
      developer.log('[로그아웃] result=SUCCESS');
    } finally {
      try {
        await _clearLocalBookshelf();
      } finally {
        state = const AuthState(status: AuthStatus.unauthenticated);
        _changingSession = false;
      }
    }
  }

  Future<void> _handleUnauthorized() => _unauthorizing ??= _revokeSession()
      .whenComplete(() => _unauthorizing = null);

  Future<void> _revokeSession() async {
    if (state.requiresLogin || _changingSession) return;
    _generation++;
    ref.read(apiClientProvider).invalidateSession();
    BookshelfDatabase.sessionGeneration++;
    final previous = state;
    // 서버 저장 모드에도 아직 업로드하지 못한 유일본이 있을 수 있다.
    // 자동 인증 해제는 토큰만 비우고 기록/소유자/dirty 큐는 보존한다.
    state = AuthState(
      status: previous.canUseApp
          ? AuthStatus.localOnly
          : AuthStatus.unauthenticated,
      user: previous.user,
      requiresLogin: true,
    );
    try {
      await _repository.clearLocalSession();
    } catch (_) {
      developer.log('[인증 해제] result=FAIL reason=storage_error');
    }
  }

  /// 로컬 기록 소유자를 검증한다. 계정 변경은 명시적 로그아웃 후 가능하다.
  Future<void> _verifyLocalOwner(int userId) async {
    final owner = await ref.read(localAuthStoreProvider).readUser();
    if (owner == null || owner.id == userId) return;
    // 보류 중인 로컬 기록을 자동 삭제하거나 새 계정으로 전송하지 않는다.
    throw const ApiException('기록을 보관한 기존 계정으로 로그인해 주세요.');
  }

  /// 다음 로그인 사용자에게 이전 계정의 책장이 남아있지 않도록 로그아웃 시
  /// 항상 비운다. SQLite뿐 아니라 이전 계정 데이터를 들고 있는 Riverpod
  /// 캐시(탭별 목록, 마지막 동기화 시각, 공개 설정, 검색/필터 상태)도 함께
  /// 무효화해야 한다 — 그렇지 않으면 재로그인 시 화면이 캐시된 이전 계정
  /// 데이터를 그대로 보여주고, `syncIfStale()`도 남은 lastSyncedAt 때문에
  /// 동기화를 건너뛴다.
  Future<void> _clearLocalBookshelf() async {
    try {
      await ref.read(bookshelfRepositoryProvider).clearLocal();
    } catch (e) {
      developer.log('[책장 로컬 DB 초기화] result=FAIL reason=${e.runtimeType}');
      rethrow;
    } finally {
      ref.invalidate(storageModeProvider);
      ref.invalidate(serverDeletePendingProvider);
      ref.invalidate(bookshelfSyncControllerProvider);
      ref.invalidate(privacySettingControllerProvider);
      ref.invalidate(finishedFilterProvider);
      // autoDispose family라 보통은 화면을 벗어나며 스스로 폐기되지만, 책
      // 기록 화면이 열린 채로 로그아웃하는 경우까지 대비해 명시적으로도 비운다.
      ref.invalidate(bookRecordControllerProvider);
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
      // 노트 동기화 컨트롤러도 같은 이유로 비운다 — 안 비우면 다음 로그인
      // 사용자 세션에서도 이전 계정의 "마지막 동기화 시각"이 캐시된 채
      // 남아, 실제로는 방금 clearLocal()로 로컬 DB의 sync_meta까지 비웠는데
      // 화면은 여전히 그 값을 들고 있게 된다. 목록/상세 provider도(autoDispose
      // family) 책 기록 화면과 같은 이유로 명시적으로 비운다.
      ref.invalidate(bookNoteSyncControllerProvider);
      ref.invalidate(bookNoteListProvider);
      ref.invalidate(bookNoteDetailProvider);
      ref.read(bookNoteSyncVersionProvider.notifier).state++;
      // 독후감 동기화 컨트롤러/목록/상세도 같은 이유로 비운다.
      ref.invalidate(bookReflectionSyncControllerProvider);
      ref.invalidate(bookReflectionListProvider);
      ref.invalidate(bookReflectionDetailProvider);
      ref.read(bookReflectionSyncVersionProvider.notifier).state++;
      // 태그 동기화 컨트롤러도 같은 이유로 비운다.
      ref.invalidate(tagSyncControllerProvider);
      ref.read(tagSyncVersionProvider.notifier).state++;
    }
  }

  /// 카테고리 마스터 데이터는 계정과 무관하지만(인증 불필요 API), 앱 전반에서
  /// 반복 조회되므로 로그인(또는 세션 복원) 시마다 서버에서 다시 받아와 로컬
  /// DB 캐시를 최신으로 맞춰둔다([BookshelfRepository.refreshCategories] —
  /// 세션 중에는 이 캐시만 쓰고 재조회하지 않으므로, staleness를 "로그인
  /// 시점"으로만 한정하기 위해 캐시 유무와 상관없이 강제로 새로 받는다).
  /// 실패해도(오프라인 등) 이미 있던 캐시는 그대로 남고, 로그인 흐름도
  /// 막지 않도록 예외를 삼키고 로그만 남긴다.
  ///
  /// 이 메서드는 `unawaited`로 호출돼 로그인 직후 화면 전환과 경쟁한다 —
  /// 화면이 [bookCategoriesProvider]를 이 갱신보다 먼저 구독해 옛 DB 캐시로
  /// `keepAlive`되면, 여기서 DB를 새로 채워도 그 provider는 세션 내내 갱신된
  /// 값을 반영하지 못한다. 성공 시 provider를 invalidate해 다음 구독이 방금
  /// 갱신된 DB 값을 다시 읽게 한다.
  Future<void> _prefetchCategories() async {
    try {
      await ref.read(bookshelfRepositoryProvider).refreshCategories();
      ref.invalidate(bookCategoriesProvider);
    } catch (e) {
      developer.log('[카테고리 캐시] result=FAIL reason=${e.runtimeType}');
    }
  }

  String _reasonOf(ApiException e) => 'status_${e.statusCode ?? 'unknown'}';
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
