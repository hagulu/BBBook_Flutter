import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../core/theme/app_theme.dart';

/// 공통 SnackBar 종류(성공/정보/에러).
enum AppSnackBarType { success, info, error }

/// 공통 SnackBar(pill 형태, 아이덴티티 컬러 반투명 배경 + 상태 아이콘).
///
/// 화면별 커스텀 SnackBar 대신 항상 이 컴포넌트를 사용한다.
class AppSnackBar {
  const AppSnackBar._();

  /// [replaceCurrent]가 true면 표시 전 대기 중인 메시지를 모두 지운다(최신
  /// 메시지만 의미 있는 연속 스캔 등 특수 흐름에서만 사용). 기본값은 false로,
  /// 기존 `ScaffoldMessenger`처럼 여러 안내가 순서대로 큐잉된다.
  static void show(
    BuildContext context, {
    required String message,
    AppSnackBarType type = AppSnackBarType.info,
    Duration duration = const Duration(seconds: 4),
    bool replaceCurrent = false,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    if (replaceCurrent) messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: _AppSnackBarContent(message: message, type: type),
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        padding: EdgeInsets.zero,
      ),
    );
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    bool replaceCurrent = false,
  }) => show(
    context,
    message: message,
    type: AppSnackBarType.success,
    duration: duration,
    replaceCurrent: replaceCurrent,
  );

  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    bool replaceCurrent = false,
  }) => show(
    context,
    message: message,
    type: AppSnackBarType.info,
    duration: duration,
    replaceCurrent: replaceCurrent,
  );

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    bool replaceCurrent = false,
  }) => show(
    context,
    message: message,
    type: AppSnackBarType.error,
    duration: duration,
    replaceCurrent: replaceCurrent,
  );
}

class _AppSnackBarContent extends StatelessWidget {
  const _AppSnackBarContent({required this.message, required this.type});

  final String message;
  final AppSnackBarType type;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (type) {
      AppSnackBarType.success => (AppColors.primary, PhosphorIconsFill.checkCircle),
      AppSnackBarType.info => (AppColors.primary, PhosphorIconsFill.info),
      // 반투명 합성 후 흰 텍스트와의 대비가 WCAG AA(4.5:1)에 못 미쳐(원본
      // AppColors.error 88% 합성 시 약 3.71:1) 검정과 섞어 더 어둡게 만든다.
      AppSnackBarType.error => (
        Color.lerp(AppColors.error, Colors.black, 0.2)!,
        PhosphorIconsFill.xCircle,
      ),
    };

    return Align(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
