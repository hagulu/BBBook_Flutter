import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../app/main_shell_tab_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_alert.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../models/external_import_models.dart';
import '../providers/external_import_providers.dart';
import 'widgets/finished_csv_import_sheets.dart';

/// 완독 기록 CSV 가져오기 화면(`my-import.md` 기능 대응). 책 추가 화면에서
/// 진입한다. CSV는 앱에서 해석하고, 저장은 다른 서비스 기록 가져오기와 같은
/// [ExternalImportController] 흐름(동기화 켜짐: 서버 Import, 꺼짐·계정 없음:
/// 로컬 저장)을 그대로 쓴다. 같은 ISBN의 기존 책은 선택에서 빠져 건너뛴다.
/// 파일을 고르면 분석이 끝나는 대로 확인 팝업을 띄워 바로 가져온다.
class FinishedCsvImportScreen extends ConsumerStatefulWidget {
  const FinishedCsvImportScreen({super.key});

  @override
  ConsumerState<FinishedCsvImportScreen> createState() =>
      _FinishedCsvImportScreenState();
}

class _FinishedCsvImportScreenState
    extends ConsumerState<FinishedCsvImportScreen> {
  ExternalImportFileReference? _file;
  var _confirmingLeave = false;
  var _allowPop = false;

  Future<void> _pickFile() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (picked == null || !mounted) return;
      final filePath = picked.path;
      if (filePath == null || filePath.isEmpty) {
        AppSnackBar.error(context, '선택한 파일을 읽을 수 없어요.');
        return;
      }
      if (path.extension(picked.name).toLowerCase() != '.csv') {
        AppSnackBar.error(context, 'CSV 파일만 선택할 수 있어요.');
        return;
      }
      setState(() {
        _file = ExternalImportFileReference(
          path: filePath,
          displayName: picked.name,
          expectedSource: ExternalImportSource.finishedCsv,
        );
      });
    } catch (_) {
      developer.log('[완독 CSV 파일 선택] result=FAIL reason=platform_error');
      if (!mounted) return;
      AppSnackBar.error(context, '파일을 선택하지 못했어요. 다시 시도해 주세요.');
    }
  }

  /// 선택을 비우면 분석 상태 provider도 함께 정리돼 다음 선택은 새로 읽는다.
  void _clearFile() {
    if (mounted) setState(() => _file = null);
  }

  /// 분석이 끝난 직후 호출된다. 취소하거나 가져오지 못하면 선택을 비워
  /// 다시 파일을 고를 수 있게 한다. 완료 결과는 [build]의 listener가 보여준다.
  Future<void> _confirmAndImport(ExternalImportFileReference file) async {
    final confirmed = await AppConfirm.show(
      context,
      title: '완독 기록을 가져올까요?',
      message: '선택한 CSV 파일의 독서 기록을 책장에 추가합니다.',
      confirmText: '가져오기',
      content: _SelectedFileChip(name: file.displayName),
    );
    if (!confirmed || !mounted) {
      _clearFile();
      return;
    }

    final provider = externalImportControllerProvider(file);
    final state = ref.read(provider);
    // 가져올 행이 하나도 없으면(모두 실패·건너뜀) 저장 없이 결과만 보여준다.
    if (state.selectedBookCount == 0) {
      await _showResult(state);
      return;
    }
    var feedback = await ref.read(provider.notifier).startImport();
    // 저장 직전 같은 ISBN의 책이 새로 확인되면 그 행은 선택에서 빠진다.
    // 고를 목록이 없는 화면이라 남은 행으로 바로 다시 가져온다.
    if (identical(feedback, ExternalImportController.newConflictFeedback)) {
      final retried = ref.read(provider);
      if (retried.selectedBookCount == 0) {
        if (mounted) await _showResult(retried);
        return;
      }
      feedback = await ref.read(provider.notifier).startImport();
    }
    if (feedback == null || !mounted) return;
    _clearFile();
    switch (feedback.type) {
      case ExternalImportFeedbackType.info:
        AppSnackBar.info(context, feedback.message);
      case ExternalImportFeedbackType.error:
        await AppAlert.show(
          context,
          title: '가져오지 못했어요',
          message: feedback.message,
        );
    }
  }

  Future<void> _showResult(ExternalImportState state) async {
    final result = state.result!;
    final successCount = state.phase == ExternalImportPhase.completed
        ? state.selectedBookCount
        : 0;
    await showFinishedCsvResultDialog(
      context,
      FinishedCsvImportSummary(
        totalCount: result.discoveredBookCount,
        successCount: successCount,
        skippedCount: result.books.length - successCount,
        failures: result.rowFailures,
      ),
    );
    if (!mounted) return;
    ref.read(mainShellTabIndexProvider.notifier).state = 0;
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  Future<void> _handlePopAttempt(bool didPop, bool importing) async {
    if (didPop || _confirmingLeave || !importing) return;
    _confirmingLeave = true;
    final confirmed = await AppConfirm.show(
      context,
      title: '가져오기 화면 닫기',
      message: '화면을 닫아도 기록 가져오기는 계속 진행돼요.',
      confirmText: '닫기',
    );
    _confirmingLeave = false;
    if (!confirmed || !mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final importState = file == null
        ? null
        : ref.watch(externalImportControllerProvider(file));
    if (file != null) {
      ref.listen(externalImportControllerProvider(file), (previous, next) {
        if (previous?.phase == next.phase) return;
        switch (next.phase) {
          case ExternalImportPhase.ready
              when previous?.phase == ExternalImportPhase.analyzing:
            _confirmAndImport(file);
          case ExternalImportPhase.failed:
            final message = next.message ?? 'CSV 파일을 확인해 주세요.';
            _clearFile();
            AppAlert.show(context, title: '파일을 가져올 수 없어요', message: message);
          case ExternalImportPhase.completed:
            if (next.needsRefresh && next.message != null) {
              AppSnackBar.info(context, next.message!);
            }
            _showResult(next);
          case ExternalImportPhase.analyzing:
          case ExternalImportPhase.ready:
          case ExternalImportPhase.importing:
            break;
        }
      });
    }
    final importing = importState?.phase == ExternalImportPhase.importing;
    final colors = AppColors.of(context);

    return PopScope(
      canPop: !importing || _allowPop,
      onPopInvokedWithResult: (didPop, _) =>
          _handlePopAttempt(didPop, importing),
      child: AppLoadingOverlay(
        isLoading: importing,
        blockInteraction: false,
        child: Scaffold(
          backgroundColor: colors.pageBackground,
          appBar: AppBar(
            title: const AppBarTitle('완독 기록 가져오기'),
            backgroundColor: colors.pageBackground,
            foregroundColor: colors.textStrong,
            elevation: 0,
          ),
          body: AbsorbPointer(
            absorbing: importing,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  '완독 기록 CSV 파일을 선택해 주세요.',
                  style: TextStyle(
                    color: colors.textStrong,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '다른 곳에 기록해 둔 완독 목록을 한 번에 추가할 수 있어요.',
                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: file == null ? _pickFile : null,
                  icon: const Icon(PhosphorIconsRegular.folderOpen, size: 18),
                  label: Text(
                    importing
                        ? '가져오는 중...'
                        : file != null
                        ? '파일 확인 중...'
                        : 'CSV 파일 선택',
                  ),
                ),
                const SizedBox(height: 20),
                _CsvManualCard(
                  onOpenPrompt: () => showFinishedCsvPromptSheet(context),
                  onOpenFormat: () => showFinishedCsvFormatSheet(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// AI로 기존 기록을 완독 CSV로 만드는 방법을 단계별 설명서처럼 안내한다.
class _CsvManualCard extends StatelessWidget {
  const _CsvManualCard({
    required this.onOpenPrompt,
    required this.onOpenFormat,
  });

  final VoidCallback onOpenPrompt;
  final VoidCallback onOpenFormat;

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
          Text(
            '내 기록 CSV 파일로 만들기',
            style: TextStyle(
              color: colors.textStrong,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'AI를 이용하면 기존 독서 기록을 CSV 파일로 쉽게 바꿀 수 있어요.',
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          const _ManualStep(
            number: 1,
            title: '기존 독서 기록 준비',
            description: '엑셀, 메모장, 다른 앱 등 어디에 기록했든 괜찮아요.',
          ),
          _ManualStep(
            number: 2,
            title: 'AI에게 변환 요청',
            description: 'AI 변환 프롬프트를 복사해 기록과 함께 전달해요.',
            actionLabel: 'AI 변환 프롬프트 보기',
            onAction: onOpenPrompt,
          ),
          _ManualStep(
            number: 3,
            title: 'CSV 파일로 저장',
            description: 'AI가 만든 결과를 .csv 파일로 저장해요.',
            actionLabel: 'CSV 형식 보기',
            onAction: onOpenFormat,
          ),
          const _ManualStep(
            number: 4,
            title: '파일 선택',
            description: '저장한 파일을 위의 CSV 파일 선택으로 가져와요.',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _ManualStep extends StatelessWidget {
  const _ManualStep({
    required this.number,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.isLast = false,
  });

  final int number;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final actionLabel = this.actionLabel;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accentSurface,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: colors.accentForeground,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textStrong,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(color: colors.textBody, fontSize: 13),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 6),
                  _StepActionChip(label: actionLabel, onTap: onAction!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepActionChip extends StatelessWidget {
  const _StepActionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surfaceSubtle,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colors.accentForeground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                PhosphorIconsRegular.caretRight,
                size: 12,
                color: colors.accentForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedFileChip extends StatelessWidget {
  const _SelectedFileChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIconsRegular.fileCsv,
            size: 18,
            color: colors.accentForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textStrong,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
