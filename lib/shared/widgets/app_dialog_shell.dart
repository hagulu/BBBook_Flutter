import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum AppDialogActionStyle { primary, neutral, destructive }

class AppDialogAction {
  const AppDialogAction({
    required this.label,
    required this.style,
    required this.onPressed,
  });

  final String label;
  final AppDialogActionStyle style;
  final VoidCallback onPressed;
}

/// [AppAlert]/[AppConfirm]가 공유하는 다이얼로그 카드 형태.
///
/// alert.png 기준(아이콘+제목, 본문, 하단 버튼 영역)의 시각 스타일을 따른다.
class AppDialogShell extends StatelessWidget {
  const AppDialogShell({
    super.key,
    this.icon,
    this.iconColor,
    this.iconBackgroundColor,
    required this.title,
    required this.message,
    required this.actions,
  });

  final IconData? icon;
  final Color? iconColor;
  final Color? iconBackgroundColor;
  final String title;
  final String message;
  final List<AppDialogAction> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Semantics(
        namesRoute: true,
        label: title,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 메시지가 길거나 텍스트 배율이 커도 다이얼로그 높이를 넘지 않도록 스크롤 영역으로 감싼다.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (icon != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor:
                                  iconBackgroundColor ??
                                  AppColors.highlightGoldSurface,
                              child: Icon(
                                icon,
                                color: iconColor ?? AppColors.highlightGold,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _Title(title)),
                          ],
                        )
                      else
                        _Title(title),
                      const SizedBox(height: 16),
                      Text(
                        message,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textBody,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (actions.length == 1)
                SizedBox(
                  width: double.infinity,
                  child: _ActionButton(actions.single),
                )
              else
                Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: _ActionButton(actions[i])),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textStrong,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(this.action);

  final AppDialogAction action;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    switch (action.style) {
      case AppDialogActionStyle.primary:
        background = AppColors.accentFill;
        foreground = AppColors.textStrong;
      case AppDialogActionStyle.neutral:
        background = AppColors.surfaceSubtle;
        foreground = AppColors.textBody;
      case AppDialogActionStyle.destructive:
        background = AppColors.error;
        foreground = Colors.white;
    }
    return ElevatedButton(
      onPressed: action.onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      child: Text(action.label),
    );
  }
}
