import 'package:flutter/material.dart';

import 'brand_config.dart';
import 'app_colors.dart';
import '../widgets/magic_motion.dart';

class AppTheme {
  static const Color primary = Color(BrandConfig.primary); // Indigo 500
  static const Color primaryDark = Color(BrandConfig.secondary); // Indigo 600
  static const Color accent = Color(BrandConfig.accent); // Purple 500
  static const Color backgroundDark = Color(
    BrandConfig.background,
  ); // Slate 900
  static const Color surfaceDark = Color(BrandConfig.surface); // Slate 800
  static const Color cardDark = Color(BrandConfig.surface);
  static const Color borderDark = Color(0xFF2C3246);

  static const Color success = Color(0xFF10B981); // Emerald 500
  static const Color warning = Color(0xFFF59E0B); // Amber 500
  static const Color error = Color(0xFFF43F5E); // Rose 500
  static const Color textLight = Color(BrandConfig.text);
  static const Color textMuted = Color(0xFF94A3B8);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      extensions: const [AppColors.dark],
      scaffoldBackgroundColor: AppColors.dark.page,
      primaryColor: primary,
      colorScheme: ColorScheme.dark(
        primary: primaryDark,
        secondary: accent,
        surface: surfaceDark,
        error: error,
        onPrimary: Colors.white,
        onSurface: AppColors.dark.text,
        onSurfaceVariant: AppColors.dark.muted,
        outline: AppColors.dark.outline,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textLight,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: textLight),
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderDark, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.dark.input,
        hintStyle: TextStyle(color: AppColors.dark.inputHint, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: const Color(0xFF171B28),
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : textMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? textLight
                : textMuted,
          ),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: primary,
        labelColor: primary,
        unselectedLabelColor: textMuted,
        labelStyle: TextStyle(fontWeight: FontWeight.bold),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: MagicPageTransitionsBuilder(),
          TargetPlatform.iOS: MagicPageTransitionsBuilder(),
          TargetPlatform.linux: MagicPageTransitionsBuilder(),
          TargetPlatform.macOS: MagicPageTransitionsBuilder(),
          TargetPlatform.windows: MagicPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      extensions: const [AppColors.light],
      scaffoldBackgroundColor: AppColors.light.page,
      primaryColor: primaryDark,
      colorScheme: ColorScheme.light(
        primary: primaryDark,
        secondary: accent,
        surface: Colors.white,
        error: error,
        onPrimary: Colors.white,
        onSurface: AppColors.light.text,
        onSurfaceVariant: AppColors.light.muted,
        outline: AppColors.light.outline,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.light.text,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: AppColors.light.text),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.light.input,
        hintStyle: TextStyle(color: AppColors.light.inputHint, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.light.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.light.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryDark, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: MagicPageTransitionsBuilder(),
          TargetPlatform.iOS: MagicPageTransitionsBuilder(),
          TargetPlatform.linux: MagicPageTransitionsBuilder(),
          TargetPlatform.macOS: MagicPageTransitionsBuilder(),
          TargetPlatform.windows: MagicPageTransitionsBuilder(),
        },
      ),
    );
  }
}
