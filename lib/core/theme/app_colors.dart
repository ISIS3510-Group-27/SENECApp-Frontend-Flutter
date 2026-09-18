import 'package:flutter/material.dart';

/// The SENECApp palette, straight from MS6.
///
/// The five brand colours carry the roles agreed in the UI/UX document; the
/// neutrals below them are the supporting greys the Figma prototype settled on
/// for cards, dividers and secondary text.
abstract final class AppColors {
  // --- Brand ---------------------------------------------------------------

  /// App canvas and bottom navigation bar.
  static const background = Color(0xFF171A21);

  /// Primary text and icons.
  static const foreground = Color(0xFFF0E2E7);

  /// Accent 1 - brand. Active chips, active nav state, destructive actions.
  static const primary = Color(0xFFA50104);

  /// Accent 2 - action. Primary CTAs, "Official" badge, active filter pill.
  static const accent = Color(0xFFFFBA08);

  /// Accent 3 - surface. Inactive chips and input backgrounds.
  static const secondary = Color(0xFF1D3557);

  // --- Supporting neutrals -------------------------------------------------

  /// Raised surface: list cards, form fields.
  static const card = Color(0xFF1E2633);

  /// A card that has been dealt with, e.g. a read notification.
  static const cardMuted = Color(0xFF1A1F2C);

  /// Labels, captions, inactive nav items.
  static const mutedForeground = Color(0xFF8B94B0);

  /// Long-form body copy - a touch brighter than [mutedForeground].
  static const bodyForeground = Color(0xFFC8CDE0);

  /// Deep backdrop behind the phone frame on wide screens.
  static const canvas = Color(0xFF0E1117);

  static const border = Color(0x0FFFFFFF); // white @ 6%
  static const borderStrong = Color(0x14FFFFFF); // white @ 8%

  // --- Per-organization accents -------------------------------------------
  // Each RSO carries its own colour so lists stay scannable at a glance.

  static const orange = Color(0xFFFF6B35);
  static const teal = Color(0xFF00C9A7);
  static const violet = Color(0xFFA78BFA);
  static const blue = Color(0xFF3B82F6);
  static const pink = Color(0xFFEC4899);
  static const indigo = Color(0xFF6366F1);
  static const amber = Color(0xFFF59E0B);
}

extension AppColorOpacity on Color {
  /// A translucent wash of this colour, used for tinted chips and icon tiles.
  ///
  /// The prototype writes these as 8-digit hex suffixes (`#A5010422`); this
  /// keeps the same intent without hard-coding a second constant per colour.
  Color get wash => withValues(alpha: 0.13);
  Color get washStrong => withValues(alpha: 0.20);
}
