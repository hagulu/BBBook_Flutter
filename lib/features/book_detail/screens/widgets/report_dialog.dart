import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';

/// 신고 사유 4종(common-interactions.md `ReportModal` 대응).
enum ReportReason {
  spam,
  offensive,
  spoiler,
  etc;

  String get apiValue => switch (this) {
    ReportReason.spam => 'SPAM',
    ReportReason.offensive => 'OFFENSIVE',
    ReportReason.spoiler => 'SPOILER',
    ReportReason.etc => 'ETC',
  };

  String get label => switch (this) {
    ReportReason.spam => '스팸/광고',
    ReportReason.offensive => '욕설/혐오',
    ReportReason.spoiler => '스포일러',
    ReportReason.etc => '기타',
  };
}

class ReportSubmission {
  const ReportSubmission({required this.reason, this.content});

  final ReportReason reason;
  final String? content;
}

/// 리뷰 신고 모달. 사유 라디오 4종, ETC 선택 시에만 상세 내용 입력창 노출.
Future<ReportSubmission?> showReportDialog(BuildContext context) {
  return showModalBottomSheet<ReportSubmission>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _ReportDialog(),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  ReportReason _reason = ReportReason.spam;
  final _contentController = TextEditingController();

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: '신고하기',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioGroup<ReportReason>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v!),
            child: Column(
              children: [
                for (final reason in ReportReason.values)
                  RadioListTile<ReportReason>(
                    value: reason,
                    activeColor: AppColors.accentForeground,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      reason.label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textBody,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_reason == ReportReason.etc) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '상세 사유를 입력해주세요',
                counterText: '',
              ),
            ),
          ],
        ],
      ),
      buttons: [
        RecordDialogButton(
          label: '신고',
          style: RecordDialogButtonStyle.destructive,
          onPressed: () => Navigator.of(context).pop(
            ReportSubmission(
              reason: _reason,
              content: _contentController.text.trim().isEmpty
                  ? null
                  : _contentController.text.trim(),
            ),
          ),
        ),
      ],
    );
  }
}
