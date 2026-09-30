import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_alert.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../server_storage_migration/providers/server_storage_migration_providers.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../providers/record_archive_provider.dart';

/// 내 기록 가져오기 안내 화면. 설정에서 진입하며, 내보낸 ZIP 파일을 고르면
/// 기존 [RecordArchiveController.run] 가져오기 흐름을 그대로 실행한다.
class RecordArchiveImportScreen extends ConsumerWidget {
  const RecordArchiveImportScreen({super.key});

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    AppLoading.show(context);
    String? message;
    try {
      message = await ref
          .read(recordArchiveProvider.notifier)
          .run(importing: true);
    } finally {
      AppLoading.hide();
    }
    if (message != null && context.mounted) {
      await AppAlert.show(context, title: '내 기록 가져오기', message: message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final isBusy =
        ref.watch(recordArchiveProvider) ||
        ref.watch(localStorageMigrationControllerProvider).isRunning ||
        ref.watch(serverStorageMigrationControllerProvider).isRunning;
    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const AppBarTitle('내 기록 가져오기'),
        backgroundColor: colors.pageBackground,
        foregroundColor: colors.textStrong,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '내보낸 기록 파일을 선택해 주세요.',
            style: TextStyle(
              color: colors.textStrong,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '설정의 내 기록 내보내기로 받은 파일만 가져올 수 있어요.',
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: isBusy ? null : () => _pickFile(context, ref),
            icon: const Icon(PhosphorIconsRegular.folderOpen, size: 18),
            label: const Text('파일 선택'),
          ),
          const SizedBox(height: 20),
          const _ArchiveInfoCard(),
        ],
      ),
    );
  }
}

class _ArchiveInfoCard extends StatelessWidget {
  const _ArchiveInfoCard();

  static const _notes = [
    '같은 ISBN의 책은 기존 책에 연결돼요.',
    '이미 가져온 기록은 중복으로 만들지 않아요.',
    '동기화가 켜져 있으면 서버에도 반영돼요.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '내 기록 파일',
                  style: TextStyle(
                    color: colors.textStrong,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.accentSurface,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '.zip',
                  style: TextStyle(
                    color: colors.accentForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final note in _notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      PhosphorIconsRegular.check,
                      size: 14,
                      color: colors.accentForeground,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note,
                      style: TextStyle(color: colors.textBody, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
