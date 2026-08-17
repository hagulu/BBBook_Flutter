import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_confirm.dart';
import 'record_dialog_shell.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// [showRereadDialog] 결과. 재독 횟수를 바꿨으면 [RereadCountUpdated], 0에서
/// '-'를 눌러 완독 취소를 확정했으면 [RereadFinishCancelled].
sealed class RereadDialogResult {
  const RereadDialogResult();
}

class RereadCountUpdated extends RereadDialogResult {
  const RereadCountUpdated(this.count);
  final int count;
}

class RereadFinishCancelled extends RereadDialogResult {
  const RereadFinishCancelled();
}

/// 재독 횟수(+/-) 팝업. 이미 0인 상태에서 '-'를 누르면 완독 취소 확인
/// 다이얼로그(`AppConfirm`)를 띄우고, 확인하면 [RereadFinishCancelled]를 반환한다.
Future<RereadDialogResult?> showRereadDialog(
  BuildContext context, {
  required int initialCount,
}) {
  return showModalBottomSheet<RereadDialogResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _RereadDialog(initialCount: initialCount),
  );
}

class _RereadDialog extends StatefulWidget {
  const _RereadDialog({required this.initialCount});

  final int initialCount;

  @override
  State<_RereadDialog> createState() => _RereadDialogState();
}

class _RereadDialogState extends State<_RereadDialog> {
  late int _count = widget.initialCount;

  Future<void> _decrement() async {
    if (_count > 0) {
      setState(() => _count--);
      return;
    }
    final confirmed = await AppConfirm.show(
      context,
      title: '완독 취소',
      message: '재독 횟수를 더 내릴 수 없습니다. 완독 상태를 취소할까요?',
      destructive: true,
    );
    if (confirmed && mounted) {
      Navigator.of(context).pop(const RereadFinishCancelled());
    }
  }

  @override
  Widget build(BuildContext context) {
    return RecordDialogShell(
      title: '재독 횟수',
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StepperButton(
            icon: PhosphorIconsRegular.minus,
            onPressed: _decrement,
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$_count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textStrong,
              ),
            ),
          ),
          _StepperButton(
            icon: PhosphorIconsRegular.plus,
            onPressed: () => setState(() => _count++),
          ),
        ],
      ),
      buttons: [
        RecordDialogButton(
          label: '확인',
          onPressed: () =>
              Navigator.of(context).pop(RereadCountUpdated(_count)),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceSubtle,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: AppColors.accentForeground, size: 20),
        ),
      ),
    );
  }
}
