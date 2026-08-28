import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../providers/storage_mode_providers.dart';
import '../services/local_storage_migration_service.dart';

/// 서버 → 로컬 저장 이전 진행 화면.
///
/// 이전이 끝나기 전에 화면을 벗어나면 안 되므로(중간에 서버 기록이 지워질
/// 수 있다는 오해를 막기 위해서라도) 진행 중에는 뒤로 가기를 막는다.
/// 실제 중단 안전성은 서비스가 순서로 보장한다
/// ([LocalStorageMigrationService] 참고).
class LocalStorageMigrationScreen extends ConsumerStatefulWidget {
  const LocalStorageMigrationScreen({super.key});

  @override
  ConsumerState<LocalStorageMigrationScreen> createState() =>
      _LocalStorageMigrationScreenState();
}

class _LocalStorageMigrationScreenState
    extends ConsumerState<LocalStorageMigrationScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(localStorageMigrationControllerProvider.notifier).start(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localStorageMigrationControllerProvider);
    final completed = state.stage == LocalStorageMigrationStage.completed;
    final failed = state.stage == LocalStorageMigrationStage.failed;

    return PopScope(
      canPop: completed || failed,
      child: Scaffold(
        appBar: AppBar(
          title: const AppBarTitle('로컬 저장으로 전환'),
          backgroundColor: AppColors.pageBackground,
          foregroundColor: AppColors.textStrong,
          automaticallyImplyLeading: completed || failed,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  switch (state.stage) {
                    LocalStorageMigrationStage.completed => '로컬 저장으로 전환했어요',
                    LocalStorageMigrationStage.failed => '전환하지 못했어요',
                    _ => '기록과 메모·독후감 이미지를 기기에 옮기고 있어요',
                  },
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textStrong,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (state.stage) {
                    LocalStorageMigrationStage.completed =>
                      '이제 기록은 이 기기에만 저장되고 서버로 올라가지 않습니다.',
                    LocalStorageMigrationStage.failed =>
                      state.failureMessage ?? '잠시 후 다시 시도해 주세요.',
                    _ =>
                      '완료될 때까지 앱을 켜 두세요. '
                          '모두 옮기기 전에는 서버 기록을 지우지 않습니다.',
                  },
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                if (state.isRunning) ...[
                  Semantics(
                    label: '이미지 내려받기 진행률',
                    value: state.imagesTotal == 0
                        ? null
                        : '${state.imagesDone} / ${state.imagesTotal}',
                    child: LinearProgressIndicator(
                      value: state.imageProgress,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(999),
                      color: AppColors.progressFill,
                      backgroundColor: AppColors.border,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                _StageRow(
                  label: '기록 내려받기',
                  done: _isDone(
                    state.stage,
                    LocalStorageMigrationStage.syncingRecords,
                  ),
                  active:
                      state.stage == LocalStorageMigrationStage.syncingRecords,
                ),
                _StageRow(
                  label: state.imagesTotal == 0
                      ? '이미지 내려받기'
                      : '이미지 내려받기 (${state.imagesDone}/${state.imagesTotal})',
                  done: _isDone(
                    state.stage,
                    LocalStorageMigrationStage.downloadingImages,
                  ),
                  active:
                      state.stage ==
                      LocalStorageMigrationStage.downloadingImages,
                ),
                _StageRow(
                  label: '저장 확인',
                  done: _isDone(
                    state.stage,
                    LocalStorageMigrationStage.verifying,
                  ),
                  active: state.stage == LocalStorageMigrationStage.verifying,
                ),
                _StageRow(
                  label: '서버 기록 정리',
                  done: state.stage == LocalStorageMigrationStage.completed,
                  active:
                      state.stage == LocalStorageMigrationStage.switchingMode,
                ),
                if (completed && state.unavailableImages > 0) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '이미지 ${state.unavailableImages}장은 서버에서 더 이상 받을 수 '
                      '없어 옮기지 못했습니다.',
                      style: const TextStyle(
                        color: AppColors.textBody,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                if (failed)
                  FilledButton(
                    onPressed: () => ref
                        .read(localStorageMigrationControllerProvider.notifier)
                        .start(),
                    child: const Text('다시 시도'),
                  ),
                if (completed)
                  FilledButton(
                    onPressed: () {
                      AppSnackBar.success(context, '로컬 저장으로 전환했습니다.');
                      Navigator.of(context).pop();
                    },
                    child: const Text('완료'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [stage]가 [target]보다 뒤 단계면 완료로 본다(실패는 완료가 아니다).
  bool _isDone(
    LocalStorageMigrationStage stage,
    LocalStorageMigrationStage target,
  ) {
    if (stage == LocalStorageMigrationStage.failed) return false;
    return stage.index > target.index &&
        stage != LocalStorageMigrationStage.idle;
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: done
                ? const Icon(
                    PhosphorIconsFill.checkCircle,
                    size: 20,
                    color: AppColors.accentForeground,
                  )
                : active
                ? const Padding(
                    padding: EdgeInsets.all(2),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    PhosphorIconsRegular.circle,
                    size: 20,
                    color: AppColors.controlInactive,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: done || active
                    ? AppColors.textStrong
                    : AppColors.textMuted,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
