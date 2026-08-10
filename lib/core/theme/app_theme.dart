import 'package:flutter/material.dart';

/// docs/porting-reference/design-system.md 기준 색상 토큰.
/// 새로운 색상은 여기에서만 추가/관리한다.
class AppColors {
  const AppColors._();

  static const primary = Color(0xFF0061A3);
  static const primaryHover = Color(0xFF004F86);
  static const accent = Color(0xFF5DAEFF);
  static const accentLight = Color(0xFFBEDAFE);

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

  static const starFilled = Color(0xFFFBBF24);
  static const masterpieceGold = Color(0xFFF5C518);
  static const masterpieceBackground = Color(0xFFFEF3C7);
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
    // 기본 M3 bodyLarge(16px)는 TextField 입력 글씨로 쓰기엔 커 보여서(design-system.md
    // 본문 14~15px 기준) 앱 전역 입력창 글씨 크기를 낮춘다.
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 14, color: AppColors.bodyText),
    ),
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
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.bodyText,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    // design-system.md: "텍스트 입력/검색창: 보더 없이 bg-[#f1f4f9] rounded-xl
    // outline-none" — 밑줄(UnderlineInputBorder) 대신 보더 없는 필 배경으로 통일.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.inputBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.tertiaryText),
      labelStyle: const TextStyle(color: AppColors.tertiaryText, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    ),
  );
}
