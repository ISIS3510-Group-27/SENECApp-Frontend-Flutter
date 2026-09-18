import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A tappable chip that filters a list or picks a value.
///
/// Chips, not tabs: these narrow a single list rather than switch between peer
/// screens, and nine of them will not fit a fixed tab bar at 390px. The three
/// named constructors are the three places the app uses them, each with the
/// active colour its role calls for.
class SelectableChip extends StatelessWidget {
  const SelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.selectedBackground,
    required this.selectedForeground,
    this.icon,
    this.background = AppColors.secondary,
    this.foreground = AppColors.mutedForeground,
    this.bordered = false,
  });

  /// Discover's category row - brand red when active.
  const SelectableChip.category({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  }) : selectedBackground = AppColors.primary,
       selectedForeground = Colors.white,
       background = AppColors.secondary,
       foreground = AppColors.mutedForeground,
       bordered = false;

  /// The Events All / My RSOs filter - amber, because it is an action pill.
  const SelectableChip.filter({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  }) : icon = null,
       selectedBackground = AppColors.accent,
       selectedForeground = AppColors.background,
       background = AppColors.secondary,
       foreground = AppColors.mutedForeground,
       bordered = false;

  /// The category picker in the create form - sits on card surfaces, so it
  /// carries a border to stay visible when unselected.
  const SelectableChip.choice({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  }) : selectedBackground = AppColors.primary,
       selectedForeground = Colors.white,
       background = AppColors.card,
       foreground = AppColors.mutedForeground,
       bordered = true;

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;
  final Color selectedBackground;
  final Color selectedForeground;
  final Color background;
  final Color foreground;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final fill = selected ? selectedBackground : background;
    final ink = selected ? selectedForeground : foreground;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      side: bordered
          ? BorderSide(
              color: selected ? selectedBackground : AppColors.borderStrong,
            )
          : BorderSide.none,
    );

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: fill,
        shape: shape,
        child: InkWell(
          onTap: () => onSelected(!selected),
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: ink),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: AppTheme.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A read-only chip - the student's interests, an organization's tags.
class StaticChip extends StatelessWidget {
  const StaticChip({
    super.key,
    required this.label,
    this.background = AppColors.secondary,
    this.foreground = AppColors.foreground,
  });

  /// A tag washed in its organization's colour.
  StaticChip.tinted({super.key, required this.label, required Color color})
    : background = color.washStrong,
      foreground = color;

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: AppTheme.body(
          size: 12,
          weight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
