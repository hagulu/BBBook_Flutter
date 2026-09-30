import 'package:flutter/material.dart';

import 'app_dialog_shell.dart';

/// 공통 Confirm 팝업(제목/내용/확인·취소 버튼).
///
/// 확인 시 true, 취소·바깥 영역 탭으로 닫히면 false를 반환한다.
/// 화면별 커스텀 확인 다이얼로그 대신 항상 이 컴포넌트를 사용한다.
class AppConfirm {
  const AppConfirm._();

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '확인',
    String cancelText = '취소',
    bool destructive = false,
  }) async {
    final result = await choose(
      context,
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      destructive: destructive,
    );
    return result ?? false;
  }

  /// [show]와 같은 팝업이지만 취소 버튼(false)과 바깥 영역 탭·뒤로 가기로
  /// 닫힘(null)을 구분해 반환한다. 취소 버튼에도 별도 동작(다시 시도 등)을
  /// 붙이고, 닫으면 아무것도 하지 않아야 할 때 사용한다.
  static Future<bool?> choose(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '확인',
    String cancelText = '취소',
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialogShell(
        title: title,
        message: message,
        actions: [
          AppDialogAction(
            label: cancelText,
            style: AppDialogActionStyle.neutral,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppDialogAction(
            label: confirmText,
            style: destructive
                ? AppDialogActionStyle.destructive
                : AppDialogActionStyle.primary,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
  }
}
