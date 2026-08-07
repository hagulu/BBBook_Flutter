import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_notifier.dart';

/// TODO: 프로필 기능 포팅 전까지 사용하는 임시 화면(이번 작업 범위 아님).
///
/// 로그아웃 버튼 등 인증 관련 진입점만 우선 제공한다
/// (기존 `placeholder_home_screen.dart`의 로그아웃 버튼을 이 탭으로 이동).
class ProfileTabPlaceholder extends ConsumerWidget {
  const ProfileTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider.select((s) => s.user));
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${user?.nickname ?? '사용자'}님, 로그인되었습니다.'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
  }
}
