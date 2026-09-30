import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_dialog_shell.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../models/external_import_models.dart';
import '../../models/finished_csv_guide.dart';

/// AI 변환 프롬프트 전문과 복사 버튼을 보여주는 바텀시트.
Future<void> showFinishedCsvPromptSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final colors = AppColors.of(sheetContext);
      return RecordDialogShell(
        title: 'AI 변환 프롬프트',
        titleTrailing: _CloseButton(sheetContext),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '기존 독서 기록과 함께 AI에게 전달해 주세요.',
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 14),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(
                  RecordDialogMetrics.controlRadius,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 복사 버튼을 프롬프트 영역 안에 둬 무엇을 복사하는지 바로 보이게 한다.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '프롬프트',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _copyPrompt(sheetContext),
                        icon: const Icon(
                          PhosphorIconsRegular.copySimple,
                          size: 16,
                        ),
                        label: const Text('복사'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: colors.accentForeground,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SelectableText(
                      FinishedCsvGuide.prompt,
                      style: TextStyle(
                        color: colors.textBody,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// CSV 헤더와 필드별 필수 여부·조건을 목록으로 보여주는 바텀시트.
Future<void> showFinishedCsvFormatSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final colors = AppColors.of(sheetContext);
      return RecordDialogShell(
        title: 'CSV 형식',
        titleTrailing: _CloseButton(sheetContext),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '첫 줄에 아래 헤더를 그대로 넣어 주세요.',
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(
                  RecordDialogMetrics.controlRadius,
                ),
              ),
              child: SelectableText(
                FinishedCsvGuide.header,
                style: TextStyle(
                  color: colors.textBody,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final field in FinishedCsvGuide.fields)
              _FieldTile(field: field),
          ],
        ),
      );
    },
  );
}

Future<void> _copyPrompt(BuildContext context) async {
  try {
    await Clipboard.setData(ClipboardData(text: FinishedCsvGuide.prompt));
    if (!context.mounted) return;
    AppSnackBar.success(context, '프롬프트를 복사했어요.');
  } catch (_) {
    if (!context.mounted) return;
    AppSnackBar.error(context, '프롬프트를 복사하지 못했어요.');
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton(this.sheetContext);

  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(PhosphorIconsRegular.x, size: 20),
      tooltip: '닫기',
      color: AppColors.of(context).textMuted,
      visualDensity: VisualDensity.compact,
      onPressed: () => Navigator.of(sheetContext).pop(),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({required this.field});

  final FinishedCsvField field;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.name,
                  style: TextStyle(
                    color: colors.textStrong,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [field.label, ?field.rule].join(' · '),
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (field.required)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.accentSurface,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '필수',
                style: TextStyle(
                  color: colors.accentForeground,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 완독 CSV 가져오기 처리 결과.
class FinishedCsvImportSummary {
  const FinishedCsvImportSummary({
    required this.totalCount,
    required this.successCount,
    required this.skippedCount,
    required this.failures,
  });

  final int totalCount;
  final int successCount;
  final int skippedCount;
  final List<ExternalImportRowFailure> failures;
}

/// 가져오기 결과 팝업. 버튼으로만 닫히며, 닫히면 호출부가 책장으로 이동한다.
Future<void> showFinishedCsvResultDialog(
  BuildContext context,
  FinishedCsvImportSummary summary,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AppDialogShell(
        title: summary.successCount > 0 ? '완독 기록을 가져왔어요' : '가져온 기록이 없어요',
        message: '총 ${summary.totalCount}건을 확인했어요.',
        content: _ResultContent(summary: summary),
        actions: [
          AppDialogAction(
            label: '책장으로 이동',
            style: AppDialogActionStyle.primary,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    ),
  );
}

class _ResultContent extends StatelessWidget {
  const _ResultContent({required this.summary});

  final FinishedCsvImportSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _CountTile(label: '등록', count: summary.successCount),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CountTile(label: '건너뜀', count: summary.skippedCount),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CountTile(
                label: '실패',
                count: summary.failures.length,
                highlight: summary.failures.isNotEmpty,
              ),
            ),
          ],
        ),
        if (summary.skippedCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '이미 책장에 있거나 파일 안에서 겹치는 ISBN은 건너뛰었어요.',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
        if (summary.failures.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            '가져오지 못한 기록',
            style: TextStyle(
              color: colors.textStrong,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          // 실패 행이 수천 개여도 보이는 항목만 만들도록 높이를 제한한
          // 목록으로 그린다(팝업 전체 스크롤과 별개로 안에서 스크롤된다).
          SizedBox(
            height: summary.failures.length <= 3 ? null : 240,
            child: ListView.builder(
              shrinkWrap: summary.failures.length <= 3,
              physics: summary.failures.length <= 3
                  ? const NeverScrollableScrollPhysics()
                  : null,
              padding: EdgeInsets.zero,
              itemCount: summary.failures.length,
              itemBuilder: (context, index) =>
                  _FailureTile(failure: summary.failures[index]),
            ),
          ),
        ],
      ],
    );
  }
}

class _FailureTile extends StatelessWidget {
  const _FailureTile({required this.failure});

  final ExternalImportRowFailure failure;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${failure.row}행 · ${failure.title ?? '제목 없음'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textStrong,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            failure.reason,
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.count,
    this.highlight = false,
  });

  final String label;
  final int count;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: highlight ? colors.error : colors.textStrong,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: colors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
