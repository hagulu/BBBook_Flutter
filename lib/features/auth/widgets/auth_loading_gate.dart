import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_notifier.dart';
import '../../../core/theme/app_theme.dart';

/// 인증 상태 확인 중에는 빈 배경만 보여준다(깜빡임 방지).
///
/// 원본(Next.js) `AuthGuard`의 로딩 처리에 대응(features/auth.md).
class AuthLoadingGate extends ConsumerWidget {
  const AuthLoadingGate({
    super.key,
    required this.child,
    this.requiresAuthentication = true,
  });

  final Widget child;
  final bool requiresAuthentication;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (isAuthLoading, canUseApp) = ref.watch(
      authNotifierProvider.select((s) => (s.isAuthLoading, s.canUseApp)),
    );
    // 인증 상태 갱신과 router redirect 사이의 프레임에서도 반대편 화면을
    // 노출하지 않는다(로그인된 사용자의 온보딩 깜빡임 방지).
    if (isAuthLoading || canUseApp != requiresAuthentication) {
      return const Scaffold(backgroundColor: AppColors.pageBackground);
    }
    return child;
  }
}
