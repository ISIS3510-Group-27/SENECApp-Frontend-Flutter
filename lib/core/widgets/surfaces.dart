import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The standard raised surface: a hairline-bordered card on the dark canvas.
///
/// Pass [onTap] and it becomes tappable with a Material ripple, which is what
/// separates this from the prototype's plain `<div>` - touch feedback is
/// expected on Android and comes free from [InkWell].
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.card,
    this.radius = AppRadius.card,
    this.border = AppColors.border,
    this.clipContents = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final Color border;

  /// Clip children to the rounded corners - needed when a card leads with a
  /// full-bleed image.
  final bool clipContents;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: border),
    );

    return Material(
      color: color,
      shape: shape,
      clipBehavior: clipContents ? Clip.antiAlias : Clip.none,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// The all-caps label that introduces a section, optionally with a trailing
/// action on the same baseline.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(text.toUpperCase(), style: AppTheme.sectionLabel),
        ?trailing,
      ],
    );
  }
}

/// One cell of a stats row: a big coloured number over a small grey caption.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            child: Text(value, style: AppTheme.heading(size: 20, color: color)),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 10, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// A rounded square holding an icon on the brand surface colour. Used as the
/// leading element of event rows and notifications.
///
/// The background stays constant rather than tinting to match [color]: an icon
/// floating on a wash of its own hue reads as coloured glass, and a list of
/// rows in seven different hues turns into a rainbow. Holding the surface still
/// leaves the icon as the only accent in the row.
class TintedIconTile extends StatelessWidget {
  const TintedIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 48,
    this.iconSize = 20,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

/// A circular icon button on the secondary surface - the notification bell, the
/// back arrow, the close button.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.background = AppColors.secondary,
    this.foreground = AppColors.foreground,
    this.size = 40,
    this.iconSize = 18,
    this.showDot = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color background;
  final Color foreground;
  final double size;
  final double iconSize;

  /// Draws the unread indicator in the top-right corner.
  final bool showDot;

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
    );

    Widget button = Material(
      color: background,
      shape: shape,
      child: InkWell(
        onTap: onPressed,
        customBorder: shape,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: iconSize, color: foreground),
              if (showDot)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}
