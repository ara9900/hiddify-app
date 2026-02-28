import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TikNet dark theme colors (minimal, modern).
abstract class TikNetColors {
  static const Color background = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceVariant = Color(0xFF252525);
  static const Color onBackground = Color(0xFFE8E8E8);
  static const Color onSurfaceVariant = Color(0xFF9E9E9E);
  static const Color primary = Color(0xFF6366F1);
  static const Color connected = Color(0xFF22C55E);
  static const Color disconnected = Color(0xFF9E9E9E);
  static const Color connecting = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color border = Color(0x14FFFFFF);
}

/// Dark theme for TikNet with Vazirmatn and RTL-friendly colors.
ThemeData tikNetDarkTheme(BuildContext context) {
  final base = ThemeData.dark(useMaterial3: true);
  final textTheme = GoogleFonts.vazirmatnTextTheme(base.textTheme).apply(
    bodyColor: TikNetColors.onBackground,
    displayColor: TikNetColors.onBackground,
  );
  return base.copyWith(
    scaffoldBackgroundColor: TikNetColors.background,
    colorScheme: ColorScheme.dark(
      surface: TikNetColors.surface,
      onSurface: TikNetColors.onBackground,
      primary: TikNetColors.primary,
      onPrimary: Colors.white,
      secondary: TikNetColors.onSurfaceVariant,
      onSecondary: TikNetColors.background,
      error: TikNetColors.error,
      onError: Colors.white,
      surfaceContainerHighest: TikNetColors.surfaceVariant,
    ),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: TikNetColors.background,
      foregroundColor: TikNetColors.onBackground,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: TikNetColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: TikNetColors.surface,
      indicatorColor: TikNetColors.primary.withValues(alpha: 0.2),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return GoogleFonts.vazirmatn(
          fontSize: 12,
          color: states.contains(WidgetState.selected) ? TikNetColors.primary : TikNetColors.onSurfaceVariant,
        );
      }),
      height: 64,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TikNetColors.primary,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.vazirmatn(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}
