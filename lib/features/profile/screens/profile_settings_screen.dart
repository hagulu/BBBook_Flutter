import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_alert.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../auth/providers/auth_access_providers.dart';
import '../../notices/providers/notices_providers.dart';
import '../../notices/screens/notices_list_screen.dart';
import '../../record_archive/providers/record_archive_provider.dart';
import '../../record_archive/screens/record_archive_import_screen.dart';
import '../../server_storage_migration/providers/server_storage_migration_providers.dart';
import '../../server_storage_migration/services/server_storage_migration_service.dart';
import '../../storage_mode/data/storage_mode_store.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../../storage_mode/services/local_storage_migration_service.dart';

/// 설정 화면. 포팅 문서(`profile-main-screen.md`) 범위 밖의 저장 방식(서버/로컬)
/// 전환 기능을 프로필 메인 화면과 분리해 여기에 둔다(프로필 탭 우측 상단
/// 설정 아이콘으로 진입).
class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 계정이 없으면 기록은 항상 이 기기에만 있다 — 서버 동기화 설정은 아예
    // 감춘다(별도의 로컬 모드 설정도 두지 않는다). ZIP 내보내기/가져오기는
    // 서버를 쓰지 않으므로 그대로 남긴다.
    final hasAccount = ref.watch(canUseAccountFeaturesProvider);
    final mode =
        ref.watch(storageModeProvider).valueOrNull ?? StorageMode.server;
    final isLocal = mode == StorageMode.local;
    final isSwitching =
        ref.watch(localStorageMigrationControllerProvider).isRunning ||
        ref.watch(serverStorageMigrationControllerProvider).isRunning ||
        ref.watch(recordArchiveProvider);

    return PopScope(
      canPop: !isSwitching,
      child: Scaffold(
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
              _SettingsGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _NoticesMenu(),
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: _ThemeModeCard(),
                    ),
                    if (hasAccount) ...[
                      const Divider(),
                      _StorageModeCard(
                        isLocal: isLocal,
                        serverCleanupPending:
                            isLocal &&
                            (ref
                                    .watch(serverDeletePendingProvider)
                                    .valueOrNull ??
                                false),
                        onSwitchToLocal: () => _startMigration(context, ref),
                        onSwitchToServer: () =>
                            _startReverseMigration(context, ref),
                        onRetryServerCleanup: () =>
                            _retryServerCleanup(context, ref),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsMenuTile(
                      icon: PhosphorIconsRegular.export,
                      label: '내 기록 내보내기',
                      onTap: isSwitching ? null : () => _export(context, ref),
                    ),
                    const Divider(),
                    _SettingsMenuTile(
                      icon: PhosphorIconsRegular.downloadSimple,
                      label: '내 기록 가져오기',
                      onTap: isSwitching
                          ? null
                          : () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const RecordArchiveImportScreen(),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const _SettingsGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OpenSourceLicenseMenu(),
                    Divider(),
                    _PolicyMenu(
                      icon: PhosphorIconsRegular.fileText,
                      label: '이용약관',
                      path: '/terms',
                    ),
                    Divider(),
                    _PolicyMenu(
                      icon: PhosphorIconsRegular.shieldCheck,
                      label: '개인정보 처리방침',
                      path: '/privacy',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _AppVersion(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    AppLoading.show(context);
    String? message;
    try {
      message = await ref
          .read(recordArchiveProvider.notifier)
          .run(importing: false);
    } finally {
      AppLoading.hide();
    }
    if (message != null && context.mounted) {
      await AppAlert.show(context, title: '내 기록 내보내기', message: message);
    }
  }

  Future<void> _startMigration(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '동기화 끄기',
      message:
          '서버의 최신 기록과 이미지를 받아 이 기기에 남기고 서버 기록은 정리합니다.\n\n'
          '동기화를 끄면 다른 기기에서 기록을 볼 수 없고, 로그아웃하면 이 기기의 기록이 삭제됩니다.\n\n'
          '계속할까요?',
      confirmText: '동기화 끄기',
    );
    if (!confirmed || !context.mounted) return;
    ref.read(serverStorageMigrationControllerProvider.notifier).dismissResult();
    ref
        .read(localStorageMigrationControllerProvider.notifier)
        .start(
          confirmProceed: (message) async {
            if (!context.mounted) return false;
            return AppConfirm.show(
              context,
              title: '동기화를 마치지 못했어요',
              message: message,
              confirmText: '동기화 끄기',
            );
          },
        );
  }

  Future<void> _startReverseMigration(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '동기화 켜기',
      message:
          '이 기기의 기록을 계정에 올려 다른 기기에서도 볼 수 있게 합니다.\n\n'
          '계속할까요?',
      confirmText: '동기화 켜기',
    );
    if (!confirmed || !context.mounted) return;
    ref.read(localStorageMigrationControllerProvider.notifier).dismissResult();
    ref.read(serverStorageMigrationControllerProvider.notifier).start();
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

class _NoticesMenu extends ConsumerWidget {
  const _NoticesMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasNew = ref.watch(hasNewNoticeProvider).valueOrNull ?? false;
    return _SettingsMenuTile(
      icon: PhosphorIconsRegular.megaphone,
      label: '공지사항',
      showBadge: hasNew,
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const NoticesListScreen()),
      ),
    );
  }
}

/// Flutter의 [LicenseRegistry]에 앱에 포함된 패키지 라이선스가 자동 등록된다.
/// [showLicensePage]는 패키지별 목록과 개별 라이선스 전문 화면을 함께 제공한다.
class _OpenSourceLicenseMenu extends StatelessWidget {
  const _OpenSourceLicenseMenu();

  @override
  Widget build(BuildContext context) {
    return _SettingsMenuTile(
      icon: PhosphorIconsRegular.scales,
      label: '오픈소스 라이선스',
      onTap: () => showLicensePage(
        context: context,
        applicationName: '북꾸러미',
        applicationLegalese: '이 앱은 오픈소스 소프트웨어를 포함합니다.',
      ),
    );
  }
}

class _PolicyMenu extends StatelessWidget {
  const _PolicyMenu({
    required this.icon,
    required this.label,
    required this.path,
  });

  final IconData icon;
  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return _SettingsMenuTile(
      icon: icon,
      label: label,
      onTap: () => launchUrl(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}

class _AppVersion extends StatelessWidget {
  const _AppVersion();

  static final _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return const SizedBox.shrink();
        return Text(
          'v ${info.version}',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.of(context).controlInactive,
            fontSize: 11,
          ),
        );
      },
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

    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '화면 테마',
          style: TextStyle(
            color: colors.textStrong,
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
                label: '다크',
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

class _StorageModeCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final localState = ref.watch(localStorageMigrationControllerProvider);
    final serverState = ref.watch(serverStorageMigrationControllerProvider);
    final isSwitching =
        localState.isRunning ||
        serverState.isRunning ||
        ref.watch(recordArchiveProvider);
    // 완료되면 진행 카드를 감추고 상태 pill(켜짐/꺼짐)만으로 결과를 보여준다.
    final Widget? migrationProgress;
    if (serverState.stage != ServerStorageMigrationStage.idle) {
      final state = serverState;
      migrationProgress = state.stage == ServerStorageMigrationStage.completed
          ? null
          : _ServerMigrationProgress(
              state: state,
              onRetry: () => ref
                  .read(serverStorageMigrationControllerProvider.notifier)
                  .start(),
            );
    } else {
      final state = localState;
      migrationProgress =
          state.stage == LocalStorageMigrationStage.idle ||
              state.stage == LocalStorageMigrationStage.completed
          ? null
          : _LocalMigrationProgress(
              state: state,
              onRetry: isLocal ? onRetryServerCleanup : onSwitchToLocal,
            );
    }

    // 서버 기록 정리 뒤에는 받지 못한 이미지를 다시 받을 수 없으므로, 완료
    // 후에도 사용자가 확인할 때까지 누락 건수를 남긴다.
    final unavailableImages =
        localState.stage == LocalStorageMigrationStage.completed
        ? localState.unavailableImages
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsMenuTile(
          icon: PhosphorIconsRegular.arrowsClockwise,
          label: '기록 동기화',
          status: isLocal ? '꺼짐' : '켜짐',
          statusIsActive: !isLocal,
          showCaret: false,
          compact: true,
          onTap: isSwitching
              ? null
              : (isLocal ? onSwitchToServer : onSwitchToLocal),
        ),
        if (migrationProgress != null) ...[
          const SizedBox(height: 8),
          migrationProgress,
          if (!isSwitching)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  ref
                      .read(localStorageMigrationControllerProvider.notifier)
                      .dismissResult();
                  ref
                      .read(serverStorageMigrationControllerProvider.notifier)
                      .dismissResult();
                },
                child: const Text('확인'),
              ),
            ),
        ],
        if (unavailableImages > 0 && !isSwitching) ...[
          const SizedBox(height: 8),
          _MigrationNotice(
            message:
                '이미지 $unavailableImages장은 서버에서 받을 수 없어 이 기기에 '
                '저장하지 못했습니다.',
            actionLabel: '확인',
            onAction: () => ref
                .read(localStorageMigrationControllerProvider.notifier)
                .dismissResult(),
          ),
        ],
        if (serverCleanupPending) ...[
          const SizedBox(height: 8),
          _MigrationNotice(
            message: '서버 기록 정리가 남아 있습니다.',
            actionLabel: '다시 시도',
            onAction: onRetryServerCleanup,
          ),
        ],
      ],
    );
  }
}

class _SettingsMenuTile extends StatelessWidget {
  const _SettingsMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.status,
    this.statusIsActive = false,
    this.showCaret = true,
    this.compact = false,
    this.showBadge = false,
  });

  final bool showBadge;
  final IconData icon;
  final String label;
  final String? status;
  final bool statusIsActive;
  final bool showCaret;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.accentForeground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15, color: colors.textStrong),
                ),
              ),
              if (showBadge) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                if (showCaret) const SizedBox(width: 8),
              ],
              if (status != null) ...[
                _SettingsStatusPill(label: status!, active: statusIsActive),
                if (showCaret) const SizedBox(width: 6),
              ],
              if (showCaret)
                Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 16,
                  color: onTap == null
                      ? colors.controlInactive
                      : colors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

class _SettingsStatusPill extends StatelessWidget {
  const _SettingsStatusPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? colors.accentGraphic : colors.controlInactive,
              shape: BoxShape.circle,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: colors.accentFill.withValues(alpha: 0.65),
                        blurRadius: 5,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: colors.textBody)),
        ],
      ),
    );
  }
}

class _LocalMigrationProgress extends StatelessWidget {
  const _LocalMigrationProgress({required this.state, required this.onRetry});

  final LocalStorageMigrationState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final running = state.isRunning;
    final failed = state.stage == LocalStorageMigrationStage.failed;
    return _MigrationProgress(
      label: switch (state.stage) {
        LocalStorageMigrationStage.syncingRecords => '기록을 내려받는 중',
        LocalStorageMigrationStage.downloadingImages =>
          '이미지 내려받는 중 (${state.imagesDone}/${state.imagesTotal})',
        LocalStorageMigrationStage.verifying => '저장 상태를 확인하는 중',
        LocalStorageMigrationStage.switchingMode => '저장 방식을 전환하는 중',
        LocalStorageMigrationStage.completed => '',
        LocalStorageMigrationStage.failed =>
          state.failureMessage ?? '전환하지 못했어요',
        LocalStorageMigrationStage.idle => '',
      },
      progress: state.imageProgress,
      running: running,
      failed: failed,
      onRetry: onRetry,
    );
  }
}

class _ServerMigrationProgress extends StatelessWidget {
  const _ServerMigrationProgress({required this.state, required this.onRetry});

  final ServerStorageMigrationState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final progress = state.stage == ServerStorageMigrationStage.uploadingImages
        ? state.imageProgress
        : state.recordProgress;
    return _MigrationProgress(
      label: switch (state.stage) {
        ServerStorageMigrationStage.preparing => '기록을 준비하는 중',
        ServerStorageMigrationStage.uploadingRecords =>
          '기록 업로드 중 (${state.recordsDone}/${state.recordsTotal})',
        ServerStorageMigrationStage.uploadingImages =>
          '이미지 업로드 중 (${state.imagesDone}/${state.imagesTotal})',
        ServerStorageMigrationStage.completing => '저장 방식을 전환하는 중',
        ServerStorageMigrationStage.completed => '',
        ServerStorageMigrationStage.failed =>
          state.failureMessage ?? '전환하지 못했어요',
        ServerStorageMigrationStage.idle => '',
      },
      progress: progress,
      running: state.isRunning,
      failed: state.stage == ServerStorageMigrationStage.failed,
      onRetry: onRetry,
    );
  }
}

class _MigrationProgress extends StatelessWidget {
  const _MigrationProgress({
    required this.label,
    required this.progress,
    required this.running,
    required this.failed,
    required this.onRetry,
  });

  final String label;
  final double? progress;
  final bool running;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: failed ? colors.error : colors.textBody,
              fontSize: 13,
            ),
          ),
          if (running) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              borderRadius: BorderRadius.circular(99),
              color: colors.progressFill,
              backgroundColor: colors.border,
            ),
          ],
          if (failed) ...[
            const SizedBox(height: 4),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }
}

class _MigrationNotice extends StatelessWidget {
  const _MigrationNotice({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: colors.textBody),
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
