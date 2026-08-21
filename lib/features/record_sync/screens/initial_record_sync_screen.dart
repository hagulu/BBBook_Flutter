import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../auth/providers/auth_notifier.dart';
import '../providers/record_sync_providers.dart';

class InitialRecordSyncGate extends ConsumerWidget {
  const InitialRecordSyncGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(
      authNotifierProvider.select((auth) => auth.user?.id),
    );
    if (userId == null) return const SizedBox.shrink();

    final syncState = ref.watch(initialRecordSyncControllerProvider(userId));
    if (syncState.phase == InitialRecordSyncPhase.completed) return child;

    return _InitialRecordSyncScreen(
      state: syncState,
      onRetry: () => ref
          .read(initialRecordSyncControllerProvider(userId).notifier)
          .retry(),
      onLogout: () async {
        AppLoading.show(context);
        try {
          await ref.read(authNotifierProvider.notifier).logout();
        } finally {
          AppLoading.hide();
        }
      },
    );
  }
}

class _InitialRecordSyncScreen extends StatelessWidget {
  const _InitialRecordSyncScreen({
    required this.state,
    required this.onRetry,
    required this.onLogout,
  });

  final InitialRecordSyncState state;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final failed = state.phase == InitialRecordSyncPhase.failed;
    final progress = state.progress;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    PhosphorIconsRegular.bookOpen,
                    size: 54,
                    color: AppColors.accentForeground,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    failed ? '기록을 준비하지 못했어요' : '내 기록을 준비하고 있어요',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textStrong,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    failed
                        ? '네트워크 상태를 확인한 뒤 다시 시도해 주세요.'
                        : '저장된 노트와 독후감을 안전하게 정리하고 있어요.\n잠시만 기다려 주세요.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (!failed) ...[
                    Semantics(
                      label: _progressLabel(state),
                      value: progress == null
                          ? null
                          : '${(progress * 100).round()}%',
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(999),
                        color: AppColors.progressFill,
                        backgroundColor: AppColors.border,
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                  _StageRow(
                    label: '서버 데이터 조회',
                    icon: PhosphorIconsRegular.downloadSimple,
                    status: _downloadStatus(state.phase),
                  ),
                  const SizedBox(height: 14),
                  _StageRow(
                    label:
                        state.phase == InitialRecordSyncPhase.saving &&
                            state.total > 0
                        ? '로컬 데이터 저장 (${state.saved}/${state.total})'
                        : '로컬 데이터 저장',
                    icon: PhosphorIconsRegular.bookOpen,
                    status: _saveStatus(state.phase),
                  ),
                  const SizedBox(height: 14),
                  _StageRow(
                    label: '완료',
                    icon: PhosphorIconsRegular.checkCircle,
                    status: _completeStatus(state.phase),
                  ),
                  if (failed) ...[
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: onRetry,
                      child: const Text('다시 시도'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(onPressed: onLogout, child: const Text('로그아웃')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _progressLabel(InitialRecordSyncState value) {
    return switch (value.phase) {
      InitialRecordSyncPhase.checking => '초기 동기화 상태 확인 중',
      InitialRecordSyncPhase.downloading => '서버 기록 조회 중',
      InitialRecordSyncPhase.saving => '로컬 기록 저장 중',
      InitialRecordSyncPhase.completed => '초기 기록 동기화 완료',
      InitialRecordSyncPhase.failed => '초기 기록 동기화 실패',
    };
  }

  _StageStatus _downloadStatus(InitialRecordSyncPhase phase) => switch (phase) {
    InitialRecordSyncPhase.checking ||
    InitialRecordSyncPhase.downloading => _StageStatus.active,
    InitialRecordSyncPhase.saving ||
    InitialRecordSyncPhase.completed => _StageStatus.completed,
    InitialRecordSyncPhase.failed => _StageStatus.failed,
  };

  _StageStatus _saveStatus(InitialRecordSyncPhase phase) => switch (phase) {
    InitialRecordSyncPhase.saving => _StageStatus.active,
    InitialRecordSyncPhase.completed => _StageStatus.completed,
    InitialRecordSyncPhase.failed => _StageStatus.failed,
    _ => _StageStatus.pending,
  };

  _StageStatus _completeStatus(InitialRecordSyncPhase phase) => switch (phase) {
    InitialRecordSyncPhase.completed => _StageStatus.completed,
    InitialRecordSyncPhase.failed => _StageStatus.failed,
    _ => _StageStatus.pending,
  };
}

enum _StageStatus { pending, active, completed, failed }

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.icon,
    required this.status,
  });

  final String label;
  final IconData icon;
  final _StageStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      _StageStatus.pending => AppColors.controlInactive,
      _StageStatus.active ||
      _StageStatus.completed => AppColors.accentForeground,
      _StageStatus.failed => AppColors.error,
    };
    final trailing = switch (status) {
      _StageStatus.active => const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.accentForeground,
        ),
      ),
      _StageStatus.completed => const Icon(
        PhosphorIconsFill.checkCircle,
        size: 20,
        color: AppColors.accentForeground,
      ),
      _StageStatus.failed => const Icon(
        PhosphorIconsRegular.warning,
        size: 20,
        color: AppColors.error,
      ),
      _StageStatus.pending => const SizedBox(width: 20),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
