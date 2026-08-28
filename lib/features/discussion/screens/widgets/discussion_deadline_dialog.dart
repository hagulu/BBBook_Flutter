import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/record_dialog_shell.dart';
import '../../utils/discussion_date.dart';

/// 마감일 설정/수정 팝업.
///
/// 날짜만 고르고 시각은 그날 `23:59:59`로 고정한다(웹과 동일). 저장에
/// 실패하면 팝업을 닫지 않고 내부에 인라인 에러를 표시한다.
///
/// [onSave]는 저장 성공 시 true를 반환해야 하며, null 인자는 "마감일 제거"다.
Future<void> showDiscussionDeadlineDialog(
  BuildContext context, {
  required DateTime? initialClosesAt,
  required Future<bool> Function(DateTime? closesAt) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DeadlineDialog(
      initialClosesAt: initialClosesAt,
      onSave: onSave,
    ),
  );
}

class _DeadlineDialog extends StatefulWidget {
  const _DeadlineDialog({required this.initialClosesAt, required this.onSave});

  final DateTime? initialClosesAt;
  final Future<bool> Function(DateTime? closesAt) onSave;

  @override
  State<_DeadlineDialog> createState() => _DeadlineDialogState();
}

class _DeadlineDialogState extends State<_DeadlineDialog> {
  late DateTime? _selected = widget.initialClosesAt?.toLocal();
  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _selected ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      helpText: '마감일 선택',
    );
    if (picked != null) setState(() => _selected = picked);
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final picked = _selected;
    // 날짜만 고르므로 그날 23:59:59까지를 마감 시각으로 본다.
    final closesAt = picked == null
        ? null
        : DateTime(picked.year, picked.month, picked.day, 23, 59, 59);

    final succeeded = await widget.onSave(closesAt);
    if (!mounted) return;
    if (succeeded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSaving = false;
      _errorMessage = '저장에 실패했습니다';
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return RecordDialogShell(
      title: '마감일 설정/수정',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '마감일이 지나면 토론이 자동으로 닫힙니다. 비워 두면 마감일 없이 열어 둡니다.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _isSaving ? null : _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selected == null
                          ? '마감일 없음'
                          : formatDiscussionDate(selected),
                      style: TextStyle(
                        fontSize: 14,
                        color: selected == null
                            ? AppColors.textMuted
                            : AppColors.textStrong,
                      ),
                    ),
                  ),
                  if (selected != null)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: const Icon(
                        PhosphorIconsRegular.x,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      onPressed: _isSaving
                          ? null
                          : () => setState(() => _selected = null),
                    ),
                  const Icon(
                    PhosphorIconsRegular.calendarBlank,
                    size: 18,
                    color: AppColors.controlInactive,
                  ),
                ],
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],
        ],
      ),
      buttons: [
        RecordDialogButton(
          label: '취소',
          style: RecordDialogButtonStyle.neutral,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        RecordDialogButton(
          label: _isSaving ? '저장 중' : '저장',
          style: RecordDialogButtonStyle.primary,
          onPressed: _isSaving ? null : _save,
        ),
      ],
    );
  }
}
