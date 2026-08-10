import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../book_record/providers/book_record_providers.dart';
import '../../bookshelf/providers/bookshelf_providers.dart';
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

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);

    final apiClient = ref.watch(apiClientProvider);
    apiClient.configureAuth(
      readAccessToken: () => state.accessToken,
      refreshAccessToken: _refreshAccessToken,
      onUnauthorized: _handleUnauthorized,
    );

    Future.microtask(_bootstrap);

    return const AuthState();
  }

  Future<void> _bootstrap() async {
    try {
      final accessToken = await _refreshAccessToken();
      if (accessToken == null) {
        // refresh token이 없거나(최초 설치) 무효화된 경우 모두 포함한다. 후자를
        // 놓치면 이전 세션의 책장이 로컬 DB에 남은 채로 다음 로그인 사용자에게
        // 노출될 수 있어(계정 데이터 격리), 로그아웃과 동일하게 비운다.
        await _clearLocalBookshelf();
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }
      await _loadCurrentUser(accessToken);
    } catch (e) {
      // secure storage 등 ApiException이 아닌 예외까지 포함해 부트스트랩이
      // authLoading에 영원히 머무르지 않도록 막는다.
      developer.log('[부트스트랩] result=FAIL reason=${e.runtimeType}');
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> _loadCurrentUser(String accessToken) async {
    try {
      final user = await _repository.fetchCurrentUser();
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        accessToken: accessToken,
      );
    } on ApiException catch (e) {
      if (e.isAuthFailure) {
        await _handleUnauthorized();
      } else {
        // 일시적인 네트워크/서버 오류: 세션(refresh token)은 유지하고 다음 진입 시
        // 재시도할 수 있도록 로그인 화면으로만 전환한다.
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    }
  }

  Future<void> loginWithGoogle() => _login(SocialProvider.google);

  Future<void> loginWithApple() => _login(SocialProvider.apple);

  /// [SocialAuthException], [ApiException]은 그대로 던져 화면(SnackBar)에서 처리한다.
  Future<void> _login(SocialProvider provider) async {
    try {
      final session = await _repository.loginWithProvider(provider);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: session.user,
        accessToken: session.accessToken,
      );
      developer.log('[소셜 로그인] provider=${provider.apiValue} result=SUCCESS');
    } on ApiException catch (e) {
      developer.log(
        '[소셜 로그인] provider=${provider.apiValue} result=FAIL reason=${_reasonOf(e)}',
      );
      rethrow;
    }
  }

  /// null은 "저장된 refresh token 없음" 또는 "실제 인증 실패(401/403)"일 때만
  /// 반환한다. 네트워크/서버 오류 등 일시적인 실패는 [ApiException]을 그대로
  /// 던져, 호출부(ApiClient)가 이를 로그아웃과 구분해서 처리하게 한다.
  Future<String?> _refreshAccessToken() async {
    try {
      final accessToken = await _repository.refreshAccessToken();
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
      developer.log(
        '[토큰 갱신] result=FAIL reason=${_reasonOf(e)} (일시 오류, 세션 유지)',
      );
      rethrow;
    }
  }

  /// 서버 로그아웃 요청이나 소셜 SDK 로그아웃이 실패해도, 상태 초기화는
  /// finally로 항상 보장한다(둘 중 하나가 막혀 로그아웃이 안 되는 상황 방지).
  Future<void> logout() async {
    try {
      await _repository.logout();
      developer.log('[로그아웃] result=SUCCESS');
    } finally {
      await _clearLocalBookshelf();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> _handleUnauthorized() async {
    try {
      await _repository.clearLocalSession();
    } finally {
      await _clearLocalBookshelf();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
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
    } finally {
      ref.invalidate(bookshelfSyncControllerProvider);
      ref.invalidate(privacySettingControllerProvider);
      ref.invalidate(finishedFilterProvider);
      // autoDispose family라 보통은 화면을 벗어나며 스스로 폐기되지만, 책
      // 기록 화면이 열린 채로 로그아웃하는 경우까지 대비해 명시적으로도 비운다.
      ref.invalidate(bookRecordControllerProvider);
      ref.read(bookshelfSyncVersionProvider.notifier).state++;
    }
  }

  String _reasonOf(ApiException e) => 'status_${e.statusCode ?? 'unknown'}';
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
