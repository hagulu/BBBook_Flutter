import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/providers/auth_notifier.dart';

/// TODO: home-feed 기능 포팅 전까지 사용하는 임시 화면.
///
/// 로그인 성공 후 이동 지점(원본 `AuthRedirect` 대상 `/feed`)이 정상 동작하는지
/// 확인하기 위한 스텁이며, 실제 홈 피드 UI는 이 작업 범위에 포함되지 않는다.
class PlaceholderHomeScreen extends ConsumerStatefulWidget {
  const PlaceholderHomeScreen({super.key});

  @override
  ConsumerState<PlaceholderHomeScreen> createState() => _PlaceholderHomeScreenState();
}

class _PlaceholderHomeScreenState extends ConsumerState<PlaceholderHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showLoginResult());
  }

  void _showLoginResult() {
    if (!mounted) return;
    final user = ref.read(authNotifierProvider).user;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('로그인 성공: ${user?.nickname ?? '알 수 없음'} (id: ${user?.id ?? '-'})'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider.select((s) => s.user));
    return Scaffold(
      appBar: AppBar(title: const Text('책책책')),
      body: Center(
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
      ),
    );
  }
}
