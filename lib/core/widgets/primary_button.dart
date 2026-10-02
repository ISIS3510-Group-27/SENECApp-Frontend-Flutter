import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The full-width call to action at the bottom of a form, in the same shape as
/// the create form's submit and the detail screen's join button.
///
/// [busy] swaps the label for a spinner and ignores taps, so a slow request
/// can't be sent twice. A null [onPressed] greys the button out.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.color = AppColors.primary,
    this.foreground = Colors.white,
  });

  /// The quieter variant, for the second choice next to a primary button.
  const PrimaryButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  }) : color = AppColors.secondary,
       foreground = AppColors.foreground;

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Material(
      color: enabled ? color : AppColors.secondary,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: enabled && !busy ? onPressed : null,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: double.infinity,
          height: 54,
          alignment: Alignment.center,
          child: busy
              ? SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: foreground,
                  ),
                )
              : Text(
                  label,
                  style: AppTheme.heading(
                    size: 16,
                    weight: FontWeight.w700,
                    color: enabled ? foreground : AppColors.mutedForeground,
                  ),
                ),
        ),
      ),
    );
  }
}
