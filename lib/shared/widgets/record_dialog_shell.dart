import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

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

/// 여러 기능의 선택·수정 폼이 공유하는 바텀시트 뼈대. 커스텀 콘텐츠가
/// 필요한 폼에도 필 버튼 시각 언어를 동일하게 적용한다.
/// `showModalBottomSheet`의 `builder`에서 반환해 사용한다(선택/수정 항목은
/// 바텀시트로, 단순 알림/확인은 `AppAlert`/`AppConfirm`을 그대로 쓴다).
class RecordDialogShell extends StatelessWidget {
  const RecordDialogShell({
    super.key,
    required this.title,
    required this.content,
    this.buttons = const [],
    this.titleTrailing,
  });

  final String title;
  final Widget content;
  final List<RecordDialogButton> buttons;

  /// 제목 오른쪽에 붙는 보조 액션(예: 항목 추가 "+" 버튼). 지정하지 않으면
  /// 제목만 표시한다.
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    // 흰 배경 컨테이너가 화면 맨 아래까지 이어지도록 SafeArea로 감싸 크기를
    // 줄이는 대신, 하단 세이프 에어리어(홈 인디케이터 등)만큼을 컨테이너
    // 내부 패딩에 더한다 — 그렇지 않으면 그 틈으로 투명한 모달 배리어가
    // 노출된다.
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          24 +
              MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textStrong,
                      ),
                    ),
                  ),
                  ?titleTrailing,
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
        background = AppColors.accentFill;
        foreground = AppColors.textStrong;
      case RecordDialogButtonStyle.neutral:
        background = AppColors.surfaceSubtle;
        foreground = AppColors.textBody;
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
