import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../auth/providers/auth_notifier.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../../storage_mode/screens/local_storage_migration_screen.dart';

/// TODO: 프로필 기능 포팅 전까지 사용하는 임시 화면(이번 작업 범위 아님).
///
/// 로그아웃과 저장 방식(서버/로컬) 전환 등 계정 관련 진입점만 우선 제공한다.
class ProfileTabPlaceholder extends ConsumerWidget {
  const ProfileTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider.select((s) => s.user));
    final mode =
        ref.watch(storageModeProvider).valueOrNull ?? StorageMode.server;
    final isLocal = mode == StorageMode.local;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${user?.nickname ?? '사용자'}님, 로그인되었습니다.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _StorageModeCard(
            isLocal: isLocal,
            serverCleanupPending:
                isLocal &&
                (ref.watch(serverDeletePendingProvider).valueOrNull ?? false),
            onSwitchToLocal: () => _startMigration(context, ref),
            onRetryServerCleanup: () => _retryServerCleanup(context, ref),
          ),
          const SizedBox(height: 28),
          Center(
            child: ElevatedButton(
              onPressed: () => _logout(context, ref, isLocal: isLocal),
              child: const Text('로그아웃'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startMigration(BuildContext context, WidgetRef ref) async {
    // 얼마나 받아야 하는지 먼저 알려 준다(로컬 DB만 세므로 서버 요청 없음).
    AppLoading.show(context);
    final int pendingImages;
    try {
      pendingImages = (await ref.read(
        localStorageMigrationPreviewProvider.future,
      )).pendingImages;
    } finally {
      AppLoading.hide();
    }
    if (!context.mounted) return;

    final confirmed = await AppConfirm.show(
      context,
      title: '로컬 저장으로 전환',
      message:
          '서버에 있는 기록과 메모 사진·독후감 이미지를 이 기기로 내려받은 뒤 '
          '서버 기록을 정리합니다.\n\n'
          '${pendingImages == 0 ? '· 아직 받지 않은 이미지는 없습니다(기록만 최신으로 맞춥니다).\n' : '· 아직 이 기기에 없는 이미지 약 $pendingImages장을 내려받습니다.\n'}'
          '· 책 표지는 기기에 저장하지 않아 오프라인에서는 보이지 않을 수 있습니다.\n'
          '· 데이터 양에 따라 시간이 걸리고 데이터 통신이 발생합니다.\n'
          '· 전환 후에는 기록이 서버에 올라가지 않아 다른 기기에서 볼 수 없습니다.\n'
          '· 태그처럼 서버에만 있는 기능은 쓸 수 없습니다.\n'
          '· 로그아웃하면 이 기기의 기록이 모두 사라집니다.\n\n'
          '계속할까요?',
      confirmText: '전환 시작',
    );
    if (!confirmed || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LocalStorageMigrationScreen(),
      ),
    );
  }

  Future<void> _retryServerCleanup(BuildContext context, WidgetRef ref) async {
    AppLoading.show(context);
    final bool cleaned;
    try {
      cleaned = await ref
          .read(localStorageMigrationControllerProvider.notifier)
          .retryServerCleanup();
    } finally {
      AppLoading.hide();
    }
    if (!context.mounted) return;
    if (cleaned) {
      AppSnackBar.success(context, '서버 기록을 정리했습니다.');
    } else {
      AppSnackBar.error(context, '서버 기록을 정리하지 못했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _logout(
    BuildContext context,
    WidgetRef ref, {
    required bool isLocal,
  }) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '로그아웃',
      message: isLocal
          // 로컬 저장 모드에서는 이 기기가 유일한 사본이다(서버 기록은 전환
          // 시점에 정리됐다).
          ? '로컬 저장 모드입니다. 로그아웃하면 이 기기에 저장된 모든 기록과 사진이 '
                '삭제되며 서버에도 사본이 없어 복구할 수 없습니다. 로그아웃할까요?'
          : '아직 서버에 동기화되지 않은 메모와 사진은 이 기기에서 '
                '삭제되어 복구할 수 없습니다. 로그아웃할까요?',
      confirmText: '로그아웃',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await ref.read(authNotifierProvider.notifier).logout();
  }
}

class _StorageModeCard extends StatelessWidget {
  const _StorageModeCard({
    required this.isLocal,
    required this.serverCleanupPending,
    required this.onSwitchToLocal,
    required this.onRetryServerCleanup,
  });

  final bool isLocal;

  /// 로컬 전환은 끝났지만 서버 기록 정리가 남은 상태.
  final bool serverCleanupPending;
  final VoidCallback onSwitchToLocal;
  final VoidCallback onRetryServerCleanup;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isLocal
                    ? PhosphorIconsRegular.deviceMobile
                    : PhosphorIconsRegular.cloud,
                size: 20,
                color: AppColors.accentForeground,
              ),
              const SizedBox(width: 8),
              Text(
                isLocal ? '로컬 저장' : '서버 저장',
                style: const TextStyle(
                  color: AppColors.textStrong,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isLocal
                ? '기록과 이미지를 이 기기에만 보관합니다. 서버로 올리지 않습니다.'
                : '기록은 서버에 저장되고, 이미지는 열어 본 것부터 이 기기에 저장됩니다.',
            style: const TextStyle(color: AppColors.textMuted, height: 1.5),
          ),
          if (!isLocal) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onSwitchToLocal,
              child: const Text('로컬 저장으로 전환'),
            ),
          ],
          if (serverCleanupPending) ...[
            const SizedBox(height: 14),
            const Text(
              '서버에 남아 있는 기록 정리가 끝나지 않았습니다. 로컬 데이터는 이미 '
              '이 기기에 있으니, 정리만 다시 실행하면 됩니다.',
              style: TextStyle(color: AppColors.error, height: 1.5),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onRetryServerCleanup,
              child: const Text('서버 기록 정리 다시 시도'),
            ),
          ],
        ],
      ),
    );
  }
}
