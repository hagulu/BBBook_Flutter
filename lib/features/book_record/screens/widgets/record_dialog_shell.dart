import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

enum RecordDialogButtonStyle { neutral, primary, destructive }

class RecordDialogButton {
  const RecordDialogButton({
    required this.label,
    required this.onPressed,
    this.style = RecordDialogButtonStyle.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final RecordDialogButtonStyle style;
}

/// 책 기록 화면의 커스텀 폼형 팝업(완독 확인/재독/출처·플랫폼/난이도/책 정보
/// 수정)이 공유하는 다이얼로그 뼈대. `AppAlert`/`AppConfirm`이 쓰는
/// `AppDialogShell`과 같은 시각 언어(라운드 24, 아이콘 원형 배지, 필 버튼)를
/// 커스텀 콘텐츠가 필요한 폼에도 그대로 적용해 팝업들이 한 가족처럼 보이게 한다.
class RecordDialogShell extends StatelessWidget {
  const RecordDialogShell({
    super.key,
    this.icon,
    this.iconColor = AppColors.primary,
    this.iconBackgroundColor = AppColors.accentLight,
    required this.title,
    required this.content,
    this.buttons = const [],
  });

  final IconData? icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final String title;
  final Widget content;
  final List<RecordDialogButton> buttons;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: iconBackgroundColor,
                      child: Icon(icon, color: iconColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.titleText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              content,
              if (buttons.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: _Button(buttons[i])),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button(this.button);

  final RecordDialogButton button;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    switch (button.style) {
      case RecordDialogButtonStyle.primary:
        background = AppColors.primary;
        foreground = Colors.white;
      case RecordDialogButtonStyle.neutral:
        background = AppColors.inputBackground;
        foreground = AppColors.bodyText;
      case RecordDialogButtonStyle.destructive:
        background = AppColors.error;
        foreground = Colors.white;
    }
    return ElevatedButton(
      onPressed: button.onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: background.withValues(alpha: 0.4),
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      child: Text(button.label),
    );
  }
}
