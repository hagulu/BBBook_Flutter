import 'package:flutter/material.dart';

/// docs/porting-reference/design-system.md 기준 색상 토큰.
/// 새로운 색상은 여기에서만 추가/관리한다.
class AppColors {
  const AppColors._();

  static const primary = Color(0xFF0061A3);
  static const primaryHover = Color(0xFF004F86);
  static const accent = Color(0xFF5DAEFF);

  static const titleText = Color(0xFF181C20);
  static const bodyText = Color(0xFF404751);
  static const tertiaryText = Color(0xFF707882);
  static const mutedIcon = Color(0xFF94A3B8);

  static const pageBackground = Color(0xFFF7F9FE);
  static const onboardingBackground = Color(0xFFF4F7FA);
  static const inputBackground = Color(0xFFF1F4F9);
  static const cardBackground = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E8ED);

  static const error = Color(0xFFE03C3C);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const warningBackground = Color(0xFFFFFBEB);
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    error: AppColors.error,
    surface: AppColors.cardBackground,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.pageBackground,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
  );
}
