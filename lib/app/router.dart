import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/providers/auth_notifier.dart';
import '../features/auth/providers/auth_state.dart';
import '../features/auth/screens/onboarding_screen.dart';
import '../features/auth/widgets/auth_loading_gate.dart';
import 'main_shell.dart';

/// Riverpod의 인증 상태 변화를 go_router의 `refresh`에 연결한다.
class _GoRouterRefreshNotifier extends ChangeNotifier {
  _GoRouterRefreshNotifier(Ref ref) {
    ref.listen(authNotifierProvider, (_, _) => notifyListeners());
  }
}

/// 인증 상태 기반 라우팅.
///
/// - `/`(온보딩): 로그인 상태면 `/feed`로 즉시 리다이렉트(원본 `AuthRedirect`).
/// - 그 외 라우트(`/feed` 등 인증 필요 화면): 미인증이면 `/`로 리다이렉트(원본 `AuthGuard`).
/// - 인증 확인 중에는 리다이렉트하지 않고 [AuthLoadingGate]가 빈 배경만 보여준다.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _GoRouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      if (authState.isAuthLoading) {
        return null;
      }

      final isOnboarding = state.matchedLocation == '/';
      final isLoggedIn = authState.status == AuthStatus.authenticated;

      if (!isLoggedIn && !isOnboarding) {
        return '/';
      }
      if (isLoggedIn && isOnboarding) {
        return '/feed';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const AuthLoadingGate(child: OnboardingScreen()),
      ),
      GoRoute(
        path: '/feed',
        builder: (context, state) => const AuthLoadingGate(child: MainShell()),
      ),
    ],
  );
});
