import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_alert.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_loading.dart';
import '../models/external_import_models.dart';
import '../providers/external_import_providers.dart';
import '../services/external_record_import_service.dart';

class ExternalImportScreen extends ConsumerWidget {
  const ExternalImportScreen({super.key, required this.file});

  final ExternalImportFileReference file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(externalImportControllerProvider(file));
    final isBusy =
        state.phase == ExternalImportPhase.analyzing ||
        state.phase == ExternalImportPhase.importing;
    return PopScope(
      canPop: !isBusy,
      child: Scaffold(
        backgroundColor: AppColors.of(context).pageBackground,
        appBar: AppBar(
          title: const AppBarTitle('다른 서비스 기록 가져오기'),
          backgroundColor: AppColors.of(context).pageBackground,
          foregroundColor: AppColors.of(context).textStrong,
        ),
        body: AppLoadingOverlay(
          isLoading: isBusy,
          child: _body(context, ref, state),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, ExternalImportState state) {
    switch (state.phase) {
      case ExternalImportPhase.analyzing:
        return const _CenteredMessage(
          icon: PhosphorIconsRegular.fileMagnifyingGlass,
          title: '파일을 확인하고 있어요',
          message: '기록 수에 따라 잠시 걸릴 수 있어요.',
        );
      case ExternalImportPhase.failed:
        return _CenteredMessage(
          icon: PhosphorIconsRegular.warningCircle,
          title: '파일을 가져올 수 없어요',
          message: state.message ?? '지원하지 않는 파일이에요.',
          actionLabel: '닫기',
          onAction: () => Navigator.of(context).pop(),
        );
      case ExternalImportPhase.completed:
        return _CenteredMessage(
          icon: PhosphorIconsRegular.checkCircle,
          title: '가져오기를 마쳤어요',
          message: state.message ?? '기록을 가져왔어요.',
          actionLabel: '확인',
          onAction: () => Navigator.of(context).pop(),
        );
      case ExternalImportPhase.ready:
      case ExternalImportPhase.importing:
        final result = state.result!;
        return _ImportPreview(
          result: result,
          importing: state.phase == ExternalImportPhase.importing,
          progress: state.progress,
          onImport: () async {
            final message = await ref
                .read(externalImportControllerProvider(file).notifier)
                .startImport();
            if (message != null && context.mounted) {
              await AppAlert.show(
                context,
                title: '가져오지 못했어요',
                message: message,
              );
            }
          },
        );
    }
  }
}

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({
    required this.result,
    required this.importing,
    required this.progress,
    required this.onImport,
  });

  final ExternalImportParseResult result;
  final bool importing;
  final ExternalImportProgress? progress;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final noteSummary =
        result.source == ExternalImportSource.bookmory && result.noteCount > 0
        ? ' · 메모 ${result.noteCount}개'
        : '';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            PhosphorIconsRegular.books,
            size: 52,
            color: colors.accentForeground,
          ),
          const SizedBox(height: 18),
          Text(
            '${result.source.label} 기록을 찾았어요',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textStrong,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '책 ${result.importableRecordCount}권$noteSummary',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textBody, fontSize: 16),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _CountRow(label: '발견한 책', count: result.discoveredBookCount),
                const SizedBox(height: 12),
                _CountRow(
                  label: '가져올 수 있는 기록',
                  count: result.importableRecordCount,
                ),
                const SizedBox(height: 12),
                _CountRow(label: '읽지 못한 항목', count: result.skippedItemCount),
                if (result.source == ExternalImportSource.bookmory) ...[
                  const SizedBox(height: 12),
                  _CountRow(label: '메모', count: result.noteCount),
                ],
              ],
            ),
          ),
          if (result.warningCount > 0) ...[
            const SizedBox(height: 14),
            Text(
              '알 수 없는 값 ${result.warningCount}건은 기본값으로 가져와요.',
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
          ],
          if (importing && progress != null) ...[
            const SizedBox(height: 22),
            LinearProgressIndicator(value: progress!.ratio),
            const SizedBox(height: 8),
            Text(
              '${progress!.completed} / ${progress!.total}',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 30),
          FilledButton(
            onPressed: importing || result.importableRecordCount == 0
                ? null
                : onImport,
            child: Text('${result.importableRecordCount}권 가져오기'),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: colors.textBody)),
        ),
        Text(
          '$count',
          style: TextStyle(
            color: colors.textStrong,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: colors.accentForeground),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textStrong,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textBody),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
