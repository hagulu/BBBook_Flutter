import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../providers/server_storage_migration_providers.dart';
import '../services/server_storage_migration_service.dart';

/// 로컬 → 서버 저장 재전환 진행 화면.
///
/// 진행 중에는 뒤로 가기를 막는다 — 도중에 화면을 벗어나도 전환 자체는
/// 계속 실행되지만, 사용자가 중단됐다고 오해해 앱을 종료하면 진행 상황을
/// 알 방법이 없다. 실패 후 재시도는 `/start`부터 완전히 새로 시작한다
/// ([ServerStorageMigrationService] 참고).
class ServerStorageMigrationScreen extends ConsumerStatefulWidget {
  const ServerStorageMigrationScreen({super.key});

  @override
  ConsumerState<ServerStorageMigrationScreen> createState() =>
      _ServerStorageMigrationScreenState();
}

class _ServerStorageMigrationScreenState
    extends ConsumerState<ServerStorageMigrationScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () =>
          ref.read(serverStorageMigrationControllerProvider.notifier).start(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serverStorageMigrationControllerProvider);
    final completed = state.stage == ServerStorageMigrationStage.completed;
    final failed = state.stage == ServerStorageMigrationStage.failed;

    return PopScope(
      canPop: completed || failed,
      child: Scaffold(
        appBar: AppBar(
          title: const AppBarTitle('서버 저장으로 전환'),
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
                    ServerStorageMigrationStage.completed => '서버 저장으로 전환했어요',
                    ServerStorageMigrationStage.failed => '전환하지 못했어요',
                    _ => '기록과 이미지를 서버로 옮기고 있어요',
                  },
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textStrong,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (state.stage) {
                    ServerStorageMigrationStage.completed =>
                      '이제 기록이 서버에 저장되어 다른 기기에서도 볼 수 있습니다.',
                    ServerStorageMigrationStage.failed =>
                      state.failureMessage ?? '잠시 후 다시 시도해 주세요.',
                    _ => '완료될 때까지 앱을 켜 두세요. 실패하면 기존 기기 기록은 그대로 유지됩니다.',
                  },
                  style: const TextStyle(color: AppColors.textMuted, height: 1.5),
                ),
                const SizedBox(height: 28),
                _StageRow(
                  label: '기록 준비',
                  done: _isDone(
                    state.stage,
                    ServerStorageMigrationStage.preparing,
                  ),
                  active: state.stage == ServerStorageMigrationStage.preparing,
                ),
                _StageRow(
                  label: state.recordsTotal == 0
                      ? '기록 업로드'
                      : '기록 업로드 (${state.recordsDone}/${state.recordsTotal})',
                  done: _isDone(
                    state.stage,
                    ServerStorageMigrationStage.uploadingRecords,
                  ),
                  active:
                      state.stage ==
                      ServerStorageMigrationStage.uploadingRecords,
                ),
                _StageRow(
                  label: state.imagesTotal == 0
                      ? '이미지 업로드'
                      : '이미지 업로드 (${state.imagesDone}/${state.imagesTotal})',
                  done: _isDone(
                    state.stage,
                    ServerStorageMigrationStage.uploadingImages,
                  ),
                  active:
                      state.stage ==
                      ServerStorageMigrationStage.uploadingImages,
                ),
                _StageRow(
                  label: '완료 처리',
                  done: completed,
                  active: state.stage == ServerStorageMigrationStage.completing,
                ),
                const SizedBox(height: 28),
                if (failed)
                  FilledButton(
                    onPressed: () => ref
                        .read(serverStorageMigrationControllerProvider.notifier)
                        .start(),
                    child: const Text('다시 시도'),
                  ),
                if (completed)
                  FilledButton(
                    onPressed: () {
                      AppSnackBar.success(context, '서버 저장으로 전환했습니다.');
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

  bool _isDone(
    ServerStorageMigrationStage stage,
    ServerStorageMigrationStage target,
  ) {
    if (stage == ServerStorageMigrationStage.failed) return false;
    return stage.index > target.index &&
        stage != ServerStorageMigrationStage.idle;
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.label, required this.done, required this.active});

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
