import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Corner radii (since the prototype leans on a 1rem base radius with larger
/// values we inspire from it)
/// for hero surfaces, so these are named by role rather than by number.
abstract final class AppRadius {
  static const chip = 12.0;
  static const card = 16.0;
  static const hero = 24.0;
  static const pill = 999.0;
}

/// Horizontal page gutter. Every screen honors this so headers, lists and
/// CTAs line up down the whole app.
const double kPageGutter = 24.0;

/// Room left at the bottom of scrolling content for the navigation bar.
const double kNavBarClearance = 112.0;

abstract final class AppTheme {
  /// Bricolage Grotesque - headings. A variable-width grotesque with enough
  /// personality to carry the mascot brand at display sizes. As proposed
  /// previously on MS6.
  static TextStyle heading({
    required double size,
    FontWeight weight = FontWeight.w800,
    Color color = AppColors.foreground,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.bricolageGrotesque(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// Nunito - body and UI. Rounded humanist terminals that stay crisp at
  /// 10-14px on the dark canvas (once again as proposed on MS6).
  static TextStyle body({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.foreground,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.nunito(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// Small all-caps label that introduces each section.
  static TextStyle get sectionLabel => body(
    size: 12,
    weight: FontWeight.w700,
    color: AppColors.mutedForeground,
    letterSpacing: 1.2,
  );

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: AppColors.foreground,
      tertiary: AppColors.accent,
      onTertiary: AppColors.background,
      surface: AppColors.background,
      onSurface: AppColors.foreground,
      surfaceContainer: AppColors.card,
      surfaceContainerHigh: AppColors.card,
      onSurfaceVariant: AppColors.mutedForeground,
      error: AppColors.primary,
      onError: Colors.white,
      outline: AppColors.borderStrong,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: GoogleFonts.nunitoTextTheme(base.textTheme).apply(
        bodyColor: AppColors.foreground,
        displayColor: AppColors.foreground,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.foreground,
        elevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.secondary,
        contentTextStyle: body(size: 13, weight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        hintStyle: body(size: 14, color: AppColors.mutedForeground),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: _fieldBorder(AppColors.borderStrong),
        enabledBorder: _fieldBorder(AppColors.borderStrong),
        focusedBorder: _fieldBorder(AppColors.primary),
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.card),
    borderSide: BorderSide(color: color),
  );
}
