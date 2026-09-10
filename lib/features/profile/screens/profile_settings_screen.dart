import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../server_storage_migration/screens/server_storage_migration_screen.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../../storage_mode/screens/local_storage_migration_screen.dart';

/// 설정 화면. 포팅 문서(`profile-main-screen.md`) 범위 밖의 저장 방식(서버/로컬)
/// 전환 기능을 프로필 메인 화면과 분리해 여기에 둔다(프로필 탭 우측 상단
/// 설정 아이콘으로 진입).
class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode =
        ref.watch(storageModeProvider).valueOrNull ?? StorageMode.server;
    final isLocal = mode == StorageMode.local;

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('설정'),
        backgroundColor: AppColors.of(context).pageBackground,
        foregroundColor: AppColors.of(context).textStrong,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ThemeModeCard(),
            const SizedBox(height: 16),
            _StorageModeCard(
              isLocal: isLocal,
              serverCleanupPending:
                  isLocal &&
                  (ref.watch(serverDeletePendingProvider).valueOrNull ?? false),
              onSwitchToLocal: () => _startMigration(context, ref),
              onSwitchToServer: () => _startReverseMigration(context, ref),
              onRetryServerCleanup: () => _retryServerCleanup(context, ref),
            ),
            const SizedBox(height: 20),
            const _OpenSourceLicenseMenu(),
          ],
        ),
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

  Future<void> _startReverseMigration(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '서버 저장으로 전환',
      message:
          '이 기기에만 있는 기록과 메모 사진·독후감 이미지를 서버로 올립니다.\n\n'
          '· 직접 등록한 책의 표지는 서버로 올라가지 않아 나중에 다시 설정해야 할 수 있습니다.\n'
          '· 데이터 양에 따라 시간이 걸리고 데이터 통신이 발생합니다.\n'
          '· 하나라도 실패하면 전체가 실패 처리되며, 이 기기의 기록은 그대로 유지됩니다.\n'
          '· 전환 후에는 기록이 서버에 저장되어 다른 기기에서도 볼 수 있습니다.\n\n'
          '계속할까요?',
      confirmText: '전환 시작',
    );
    if (!confirmed || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ServerStorageMigrationScreen(),
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
}

/// Flutter의 [LicenseRegistry]에 앱에 포함된 패키지 라이선스가 자동 등록된다.
/// [showLicensePage]는 패키지별 목록과 개별 라이선스 전문 화면을 함께 제공한다.
class _OpenSourceLicenseMenu extends StatelessWidget {
  const _OpenSourceLicenseMenu();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        PhosphorIconsRegular.scales,
        color: colors.accentForeground,
        size: 22,
      ),
      title: Text(
        '오픈소스 라이선스',
        style: TextStyle(color: colors.textMuted, fontSize: 14),
      ),
      trailing: Icon(
        PhosphorIconsRegular.caretRight,
        color: colors.controlInactive,
        size: 18,
      ),
      onTap: () => showLicensePage(
        context: context,
        applicationName: '책책책',
        applicationLegalese: '이 앱은 오픈소스 소프트웨어를 포함합니다.',
      ),
    );
  }
}

class _ThemeModeCard extends ConsumerWidget {
  const _ThemeModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    Future<void> select(ThemeMode selectedMode) async {
      final saved = await ref
          .read(themeModeProvider.notifier)
          .select(selectedMode);
      if (!saved && context.mounted) {
        AppSnackBar.error(context, '테마 설정을 저장하지 못했습니다. 다시 선택해 주세요.');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '화면 테마',
          style: TextStyle(
            color: AppColors.of(context).textStrong,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<ThemeMode>(
          expandedInsets: EdgeInsets.zero,
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            ),
          ),
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              label: _ThemeModeButtonLabel(
                icon: PhosphorIconsRegular.deviceMobile,
                label: '시스템',
              ),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: _ThemeModeButtonLabel(
                icon: PhosphorIconsRegular.sun,
                label: '라이트',
              ),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: _ThemeModeButtonLabel(
                icon: PhosphorIconsRegular.moon,
                label: '다크 테마',
              ),
            ),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            select(selection.single);
          },
        ),
      ],
    );
  }
}

class _ThemeModeButtonLabel extends StatelessWidget {
  const _ThemeModeButtonLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 5),
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }
}

class _StorageModeCard extends StatelessWidget {
  const _StorageModeCard({
    required this.isLocal,
    required this.serverCleanupPending,
    required this.onSwitchToLocal,
    required this.onSwitchToServer,
    required this.onRetryServerCleanup,
  });

  final bool isLocal;

  /// 로컬 전환은 끝났지만 서버 기록 정리가 남은 상태.
  final bool serverCleanupPending;
  final VoidCallback onSwitchToLocal;
  final VoidCallback onSwitchToServer;
  final VoidCallback onRetryServerCleanup;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.of(context).border),
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
                color: AppColors.of(context).accentForeground,
              ),
              const SizedBox(width: 8),
              Text(
                isLocal ? '로컬 저장' : '서버 저장',
                style: TextStyle(
                  color: AppColors.of(context).textStrong,
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
            style: TextStyle(
              color: AppColors.of(context).textMuted,
              height: 1.5,
            ),
          ),
          if (!isLocal) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onSwitchToLocal,
              child: const Text('로컬 저장으로 전환'),
            ),
          ] else ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onSwitchToServer,
              child: const Text('서버 저장으로 전환'),
            ),
          ],
          if (serverCleanupPending) ...[
            const SizedBox(height: 14),
            Text(
              '서버에 남아 있는 기록 정리가 끝나지 않았습니다. 로컬 데이터는 이미 '
              '이 기기에 있으니, 정리만 다시 실행하면 됩니다.',
              style: TextStyle(color: AppColors.of(context).error, height: 1.5),
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
