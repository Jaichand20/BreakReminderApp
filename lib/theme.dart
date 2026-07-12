import 'package:flutter/material.dart';

/// Mirrors the original app's CSS custom properties 1:1.
class AppColors {
  AppColors._();

  static const pageBg = Color(0xFF0D0D0E);
  static const surface = Color(0xFF18181B);
  static const surface2 = Color(0xFF1F1F23);
  static const inkPrimary = Color(0xFFF5F5F7);
  static const inkSecondary = Color(0xFFA2A2A8);
  static const inkMuted = Color(0xFF6F6F76);
  static const border = Color(0x14FFFFFF);
  static const gridLine = Color(0x12FFFFFF);
  static const accent = Color(0xFFFF375F);
  static const accentLight = Color(0xFFFF5F6D);

  static const heat0 = Color(0xFF232326);
  static const heat1 = Color(0xFF4A1F28);
  static const heat2 = Color(0xFF9C2F45);
  static const heat3 = Color(0xFFE8394F);
  static const heat4 = Color(0xFFFF5F6D);

  static const heatLevels = [heat0, heat1, heat2, heat3, heat4];
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.pageBg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      surface: AppColors.surface,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.inkPrimary,
      displayColor: AppColors.inkPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.pageBg,
      foregroundColor: AppColors.inkPrimary,
      elevation: 0,
    ),
    cardColor: AppColors.surface,
    dividerColor: AppColors.border,
  );
}
