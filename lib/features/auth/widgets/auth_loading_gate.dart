import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_notifier.dart';

/// 인증 상태 확인 중에는 빈 배경만 보여준다(깜빡임 방지).
///
/// 원본(Next.js) `AuthGuard`의 로딩 처리에 대응(features/auth.md).
class AuthLoadingGate extends ConsumerWidget {
  const AuthLoadingGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthLoading = ref.watch(
      authNotifierProvider.select((s) => s.isAuthLoading),
    );
    if (isAuthLoading) {
      return const Scaffold(backgroundColor: Colors.white);
    }
    return child;
  }
}
