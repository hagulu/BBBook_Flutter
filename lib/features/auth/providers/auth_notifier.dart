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
import '../../server_storage_migration/providers/server_storage_migration_providers.dart';
import '../../tag/providers/tag_providers.dart';
import '../data/auth_api.dart' show SocialProvider;
import '../data/auth_repository.dart';
import '../models/auth_user.dart';
import '../models/standalone_session.dart';
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
  Future<void>? _refreshingSanction;
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
      onSanctioned: refreshCurrentUser,
      prepareSession: ensureSession,
      onUserRetry: () => _retryAfter = null,
    );

    Future.microtask(_bootstrap);

    return const AuthState();
  }

  Future<void> _bootstrap() async {
    try {
      final store = ref.read(localAuthStoreProvider);
      // 로그인 없이 사용하기로 진입한 상태는 앱을 다시 켜도 유지한다. 서버
      // 계정이 없으므로 세션 복원도 시도하지 않는다.
      if (await store.isStandaloneSessionActive()) {
        state = const AuthState(status: AuthStatus.standalone);
        return;
      }
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
    if (state.isStandalone) return;
    await recoverSession();
    if (state.isAuthLoading) {
      state = AuthState(status: AuthStatus.unauthenticated, user: state.user);
    }
  }

  /// 로그인 없이 사용하기. 임시 서버 계정을 만들지 않고 저장 모드만 기기
  /// 로컬로 고정한다 — 동기화·push 게이트가 이미 그 모드를 보고 있어
  /// ([BookshelfRepository.sync], [BackgroundRecordSync]) 기록 계열 코드에
  /// 별도의 비로그인 분기를 두지 않아도 서버와 통신하지 않는다.
  ///
  /// 로컬 저장 모드로 로그아웃하며 남겨 둔 기록이 있으면 그대로 이어서 쓴다
  /// (로그아웃 시 소유자를 계정 없음으로 바꿔 두었다 — [_detachAccountFromRecords]).
  Future<void> continueWithoutAccount() async {
    await _localReady.future;
    if (_changingSession || state.canUseApp) return;
    _changingSession = true;
    try {
      final localStore = ref.read(localAuthStoreProvider);
      // 저장 모드와 세션 표시를 한 트랜잭션으로 함께 남긴다 — 둘 중 하나만
      // 반영된 채 앱이 종료되면 다음 실행의 조회 기준이 어긋난다.
      await ref
          .read(storageModeStoreProvider)
          .switchToStandalone(alongside: localStore.startStandaloneSessionIn);
      // 계정을 쓰지 않기로 한 이상 남아 있던 토큰도 들고 있지 않는다(이 상태의
      // 요청은 어차피 세션을 만들지 않는다 — [ensureSession]).
      try {
        await _repository.clearLocalSession();
      } catch (_) {
        developer.log('[계정 없이 시작] result=WARN reason=storage_error');
      }
      _generation++;
      ref.read(apiClientProvider).invalidateSession();
      _retryAfter = null;
      state = const AuthState(status: AuthStatus.standalone);
      developer.log('[계정 없이 시작] result=SUCCESS');
      _invalidateRecordCaches();
      unawaited(_prefetchCategories());
    } catch (e) {
      developer.log('[계정 없이 시작] result=FAIL reason=${e.runtimeType}');
      rethrow;
    } finally {
      _changingSession = false;
    }
  }

  /// 로컬 화면은 이 작업을 기다리지 않는다. 모든 인증 API는 이 Future를
  /// 공유해 계정 확인 이전에 기록을 다른 계정으로 전송하지 않는다.
  Future<void> ensureSession() async {
    await _localReady.future;
    // 계정이 없는 사용자는 세션 자체가 없다. 인증이 필요한 요청은 여기서 바로
    // 끊어 익명 요청이 401을 받아 인증 해제 흐름을 타는 일이 없게 한다(인증이
    // 필요 없는 공개 조회는 [ApiClient]가 이 실패를 받아 토큰 없이 보낸다).
    if (state.isStandalone) {
      throw const ApiException('로그인이 필요한 기능입니다.');
    }
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
    Future<StandaloneRecordAction?> Function()? askStandaloneRecordAction,
  }) => _login(
    SocialProvider.google,
    confirmAccountChange: confirmAccountChange,
    askStandaloneRecordAction: askStandaloneRecordAction,
  );

  Future<bool> loginWithApple({
    Future<bool> Function()? confirmAccountChange,
    Future<StandaloneRecordAction?> Function()? askStandaloneRecordAction,
  }) => _login(
    SocialProvider.apple,
    confirmAccountChange: confirmAccountChange,
    askStandaloneRecordAction: askStandaloneRecordAction,
  );

  Future<bool> loginWithKakao({
    Future<bool> Function()? confirmAccountChange,
    Future<StandaloneRecordAction?> Function()? askStandaloneRecordAction,
  }) => _login(
    SocialProvider.kakao,
    confirmAccountChange: confirmAccountChange,
    askStandaloneRecordAction: askStandaloneRecordAction,
  );

  Future<bool> loginWithNaver({
    Future<bool> Function()? confirmAccountChange,
    Future<StandaloneRecordAction?> Function()? askStandaloneRecordAction,
  }) => _login(
    SocialProvider.naver,
    confirmAccountChange: confirmAccountChange,
    askStandaloneRecordAction: askStandaloneRecordAction,
  );

  /// [SocialAuthException], [ApiException]은 그대로 던져 화면(SnackBar)에서 처리한다.
  Future<bool> _login(
    SocialProvider provider, {
    Future<bool> Function()? confirmAccountChange,
    Future<StandaloneRecordAction?> Function()? askStandaloneRecordAction,
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
      final loginSession = await _repository.loginWithProvider(provider);
      final currentUser = await _repository.fetchCurrentUser(
        accessToken: loginSession.accessToken,
      );
      final session = AuthSession(
        user: currentUser,
        accessToken: loginSession.accessToken,
        refreshToken: loginSession.refreshToken,
        expiresIn: loginSession.expiresIn,
      );
      final continued = await _adoptLocalRecordsForLogin(
        session.user,
        confirmAccountChange: confirmAccountChange,
        askStandaloneRecordAction: askStandaloneRecordAction,
        // 계정 없이 쓰던 기록을 이어받는 두 경로(아래)는 이 콜백을 로컬 DB
        // 커밋보다 먼저 실행한다 — 세션 저장이 실패하면 DB에 손대지 않은
        // 채로 끝나, 다음 실행이 여전히 계정 없는 상태로 안전하게 복원된다.
        // 반대 순서면 DB만 새 계정으로 바뀐 채 세션 저장이 실패할 수 있고,
        // 그러면 메모리 상태는 계정 없음으로 남아 이미 그 계정 소유가 된
        // 기록을 찾지 못한다.
        persistSession: () async {
          await ref.read(localAuthStoreProvider).saveUser(session.user);
          await _repository.saveSession(session);
        },
      );
      if (!continued) return false;
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

  /// 로그인 직전, 이 기기에 남아 있는 로컬 기록을 새 계정으로 어떻게 이어
  /// 갈지 정한다. 계속 진행해도 되면 true, 사용자가 취소했으면 false.
  ///
  /// 계정 없이 쓰던 사용자의 기록은 지우지 않는다 — 소유자만 새 계정으로
  /// 바꿔 끼우고([LocalAuthStore.rekeyRecordOwner]) 로컬 저장 모드를 그대로
  /// 유지한다. "계정에 올리기"를 고른 경우에도 여기서 업로드하지 않고, 기존
  /// 로컬 → 서버 저장 방식 전환(Import) 흐름을 호출부가 그대로 실행한다
  /// (`ServerStorageMigrationScreen` — 새 이전 기능을 만들지 않는다).
  Future<bool> _adoptLocalRecordsForLogin(
    AuthUser user, {
    required Future<bool> Function()? confirmAccountChange,
    required Future<StandaloneRecordAction?> Function()?
    askStandaloneRecordAction,
    required Future<void> Function() persistSession,
  }) async {
    final localStore = ref.read(localAuthStoreProvider);
    final storageMode = ref.read(storageModeStoreProvider);

    if (await storageMode.isStandaloneOwned()) {
      if (!await localStore.hasLocalRecords()) {
        // 기록 없이 둘러보기만 한 경우 — 흔적만 지우고 평소 로그인과 같은
        // 서버 저장 모드로 시작한다(최초 기록 동기화가 정상 동작한다).
        // 저장 모드 삭제와 standalone 세션 표시 삭제는 한 트랜잭션으로
        // 묶는다 — 일부만 반영된 채 종료되면 저장 모드는 서버인데
        // standalone 표시만 남는 조합이 복원된다.
        await persistSession();
        await storageMode.resetToServer(
          alongside: (txn) => localStore.endStandaloneSessionIn(txn),
        );
        return true;
      }
      final action = await askStandaloneRecordAction?.call();
      if (action == null) return false;
      await persistSession();
      // 기록 소유자·저장 모드 소유자·세션 표시를 한 트랜잭션으로 함께 바꾼다.
      // 일부만 반영된 채 앱이 종료되면 다음 실행이 여전히 계정 없는 상태로
      // 복원되면서 소유자만 계정으로 바뀐 노트·독후감을 못 찾는다.
      await storageMode.adoptOwner(
        user.id,
        alongside: (txn) async {
          await localStore.rekeyRecordOwnerIn(
            txn,
            from: standaloneOwnerUserId,
            to: user.id,
          );
          await localStore.endStandaloneSessionIn(txn);
        },
      );
      _invalidateRecordCaches();
      developer.log(
        '[로그인 전환] userId=${user.id} records=${action.name} result=SUCCESS',
      );
      return true;
    }

    final owner = await localStore.readUser();
    // 소유자 정보가 유실된 구형 기록도 새 로그인 계정에 임의로 합치지 않는다.
    final needsReset = owner != null
        ? owner.id != user.id
        : await localStore.hasLocalRecords();
    if (!needsReset) {
      await persistSession();
      return true;
    }
    if (confirmAccountChange == null || !await confirmAccountChange()) {
      return false;
    }
    _generation++;
    ref.read(apiClientProvider).invalidateSession();
    await _clearLocalBookshelf();
    await persistSession();
    return true;
  }

  /// null은 "저장된 refresh token 없음" 또는 "실제 인증 실패(401/403)"일 때만
  /// 반환한다. 네트워크/서버 오류 등 일시적인 실패는 [ApiException]을 그대로
  /// 던져, 호출부(ApiClient)가 이를 로그아웃과 구분해서 처리하게 한다.
  Future<String?> _refreshAccessToken() {
    // 계정이 없는 사용자에게는 갱신할 세션 자체가 없다. null을 돌려주면
    // [ApiClient]가 인증 해제(로그아웃) 흐름으로 오인하므로 오류로 끊는다.
    if (state.isStandalone) {
      return Future.error(const ApiException('로그인이 필요한 기능입니다.'));
    }
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
  ///
  /// 로컬 데이터 처리는 현재 저장 방식을 따른다.
  /// - 서버 동기화 모드: 서버에 사본이 있으므로 이 계정의 로컬 기록을 지운다
  ///   (다음 로그인 사용자에게 남지 않고, 재로그인하면 다시 내려받는다).
  /// - 로컬 저장 모드: 서버에 사본이 없는 유일본이다. 기록은 그대로 두고
  ///   계정만 떼어내, 이후 "로그인 없이 사용하기"로 그대로 이어 쓸 수 있게
  ///   한다([_detachAccountFromRecords]).
  ///
  /// [deletingAccount]는 회원 탈퇴 직후에만 true로 넘긴다 — 계정을 지운
  /// 이상 "로그인 없이 사용하기"로 이어 쓸 대상 자체가 없으므로, 저장
  /// 방식과 무관하게 로컬 기록·이미지를 항상 지운다([ProfileEditScreen]이
  /// "모든 독서 기록과 데이터가 영구적으로 삭제됩니다"로 이미 확인받았다 —
  /// 이 약속을 지키려면 로컬 저장 모드에서도 예외를 두면 안 된다).
  Future<void> logout({bool deletingAccount = false}) async {
    _changingSession = true;
    _generation++;
    ref.read(apiClientProvider).invalidateSession();
    BookshelfDatabase.sessionGeneration++;
    // 로그아웃 처리 중 DB가 바뀌기 전에 현재 저장 방식과 소유자를 확정해 둔다.
    final keepRecords = !deletingAccount && await _readIsLocalStorage();
    final previousUserId = state.user?.id;
    try {
      try {
        await _restoring;
        await _refreshing;
      } catch (_) {}
      await _unauthorizing;
      await _repository.logout();
      developer.log(
        '[로그아웃] result=SUCCESS mode=${keepRecords ? 'LOCAL' : 'SERVER'}',
      );
    } finally {
      try {
        if (keepRecords) {
          await _detachAccountFromRecords(previousUserId);
        } else {
          await _clearLocalBookshelf();
        }
      } finally {
        state = const AuthState(status: AuthStatus.unauthenticated);
        _changingSession = false;
      }
    }
  }

  /// 저장 방식 조회가 실패해도 로그아웃 자체는 진행한다. 판단이 서지 않으면
  /// 기존 동작(로컬 정리)으로 되돌려 이전 계정 기록이 남지 않게 한다.
  Future<bool> _readIsLocalStorage() async {
    try {
      return await ref.read(storageModeStoreProvider).isLocal();
    } catch (e) {
      developer.log('[로그아웃 저장 방식 확인] result=FAIL reason=${e.runtimeType}');
      return false;
    }
  }

  /// 로컬 저장 모드 로그아웃: 기록·이미지는 그대로 두고 소유자만 계정에서
  /// 떼어낸다. 계정 정보(`local_auth_user`)를 지우지 않으면 다음 실행에서
  /// 로그인 없이 그 계정으로 복원되고, 소유자를 그대로 두면 이후 "로그인
  /// 없이 사용하기"로 진입했을 때 노트·독후감이 조회되지 않는다.
  Future<void> _detachAccountFromRecords(int? previousUserId) async {
    try {
      final localStore = ref.read(localAuthStoreProvider);
      final storageMode = ref.read(storageModeStoreProvider);
      // 인증이 먼저 풀려 `state.user`가 비어 있는 채로 로그아웃할 수 있다.
      // 소유자를 모른 채 저장 모드만 바꾸면 노트·독후감이 조회 기준과 어긋나
      // 통째로 보이지 않으므로, 로컬에 남은 소유자 정보를 끝까지 찾는다.
      final ownerUserId =
          previousUserId ??
          await storageMode.ownerUserId() ??
          (await localStore.readUser())?.id;
      if (ownerUserId == null) {
        // 여기까지 와도 모르면 기록과 저장 모드를 그대로 둔다 — 잘못 바꾸는
        // 것보다 다음 로그인에서 계정 변경 확인을 받는 편이 안전하다.
        developer.log('[로컬 기록 계정 분리] result=SKIP reason=owner_unknown');
        await localStore.clearUser();
        await localStore.endStandaloneSession();
        return;
      }
      // 기록 소유자·저장 모드 소유자·계정 정보를 한 트랜잭션으로 함께 바꾼다.
      // 일부만 반영된 채 앱이 종료되면 다음 실행이 옛 계정으로 복원되면서
      // 소유자가 이미 바뀐 노트·독후감을 못 찾는다.
      await storageMode.switchToStandalone(
        alongside: (txn) async {
          await localStore.rekeyRecordOwnerIn(
            txn,
            from: ownerUserId,
            to: standaloneOwnerUserId,
          );
          await localStore.clearUserIn(txn);
          // 로그아웃 직후에는 로그인 화면으로 돌아간다. "로그인 없이
          // 사용하기"를 다시 고를 때 비로소 그 상태가 된다.
          await localStore.endStandaloneSessionIn(txn);
        },
      );
    } catch (e) {
      developer.log('[로컬 기록 계정 분리] result=FAIL reason=${e.runtimeType}');
    } finally {
      _invalidateRecordCaches();
    }
  }

  Future<void> _handleUnauthorized() => _unauthorizing ??= _revokeSession()
      .whenComplete(() => _unauthorizing = null);

  /// 서버 정책 변경을 알리는 USER_SANCTIONED 응답을 받으면 한 번만 재조회한다.
  Future<void> refreshCurrentUser() => _refreshingSanction ??=
      _fetchCurrentUser().whenComplete(() => _refreshingSanction = null);

  Future<void> _fetchCurrentUser() async {
    final generation = _generation;
    try {
      if (!state.isLoggedIn && state.user != null && !state.requiresLogin) {
        // 오프라인 로컬 상태에서 앱으로 돌아온 경우 세션 복원이 이미
        // /api/users/me를 조회하므로 그 결과를 그대로 사용한다.
        await ensureSession();
        return;
      }
      if (!state.isLoggedIn || state.accessToken == null) return;
      final user = await _repository.fetchCurrentUser();
      if (generation != _generation || !state.isLoggedIn) return;
      state = AuthState(
        status: state.status,
        user: user,
        accessToken: state.accessToken,
      );
      await ref.read(localAuthStoreProvider).saveUser(user);
      ref.invalidate(privacySettingControllerProvider);
      developer.log(
        '[징계 상태 조회] api=/api/users/me userId=${user.id} result=SUCCESS',
      );
    } catch (e) {
      developer.log(
        '[징계 상태 조회] api=/api/users/me userId=${state.user?.id} '
        'result=FAIL reason=${e.runtimeType}',
      );
    }
  }

  Future<void> _revokeSession() async {
    // 계정이 없는 사용자에게는 해제할 세션이 없다. 공개 조회 요청이 어쩌다
    // 401을 받아도 로컬 전용 상태를 건드리지 않는다.
    if (state.isStandalone) return;
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
      _invalidateRecordCaches();
    }
  }

  /// 기록 계열 Riverpod 캐시를 통째로 비운다.
  ///
  /// 로컬 DB를 지울 때뿐 아니라, 지우지 않고 소유자만 바꾸는 경우(계정 없이
  /// 쓰던 기록을 로그인 계정으로 넘기거나 그 반대)에도 반드시 필요하다 —
  /// 노트·독후감 목록/상세 provider는 소유자 id를 인자로 캐시하므로, 비우지
  /// 않으면 화면이 이전 소유자 기준의 빈 목록을 계속 보여준다.
  void _invalidateRecordCaches() {
    ref.invalidate(storageModeProvider);
    ref.invalidate(localStorageMigrationControllerProvider);
    ref.invalidate(serverStorageMigrationControllerProvider);
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
