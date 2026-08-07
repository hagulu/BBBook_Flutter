import 'package:flutter/material.dart';

import 'app_dialog_shell.dart';

/// 공통 Alert 팝업(제목/내용/확인 버튼).
///
/// 화면별 커스텀 팝업 대신 항상 이 컴포넌트를 사용한다.
class AppAlert {
  const AppAlert._();

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '확인',
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialogShell(
        title: title,
        message: message,
        actions: [
          AppDialogAction(
            label: confirmText,
            style: AppDialogActionStyle.primary,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }
}
