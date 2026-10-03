import 'package:flutter/material.dart';

import '../../core/assets/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Logo, overline, title and a line of explanation: the top of every screen
/// shown before the student is in.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Image.asset(
            BrandAssets.logo,
            width: 72,
            height: 72,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'UNIANDES · BOGOTÁ',
          style: AppTheme.body(
            size: 11,
            weight: FontWeight.w700,
            color: AppColors.mutedForeground,
            letterSpacing: 1.8,
          ),
        ),
        Text(title, style: AppTheme.heading(size: 26, height: 1.2)),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: AppTheme.body(
            size: 14,
            height: 1.4,
            color: AppColors.bodyForeground,
          ),
        ),
      ],
    );
  }
}

/// A tinted box with a short message: gold for information, red for errors.
class AuthMessage extends StatelessWidget {
  const AuthMessage.info(this.text, {super.key}) : _color = AppColors.accent;

  const AuthMessage.error(this.text, {super.key}) : _color = AppColors.primary;

  final String text;
  final Color _color;

  bool get _isError => _color == AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: _isError,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: _isError ? 0.18 : 0.08),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: _color.withValues(alpha: 0.35)),
        ),
        child: Text(
          text,
          style: AppTheme.body(
            size: 12,
            height: 1.5,
            weight: FontWeight.w600,
            // The brand red is too dark to read on the canvas; errors keep
            // light text and let the tinted box carry the colour.
            color: _isError ? AppColors.foreground : AppColors.accent,
          ),
        ),
      ),
    );
  }
}
