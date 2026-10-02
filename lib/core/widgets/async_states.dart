import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Stands in for a list while it loads.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}

/// Stands in for a list that couldn't be loaded, with a way to try again.
/// Laid out like the screens' empty states.
class ErrorBlock extends StatelessWidget {
  const ErrorBlock({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kPageGutter,
        vertical: 40,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 40,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(height: 12),
          Text("Couldn't load this", style: AppTheme.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Try again',
              style: AppTheme.body(
                size: 13,
                weight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
