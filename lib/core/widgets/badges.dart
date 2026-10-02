import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The amber "Official" marker for university-recognised organizations.
///
/// Two sizes: [OfficialBadge] on covers and carousel cards where there is room
/// for the word, and [OfficialDot] on dense list rows where there is not.
class OfficialBadge extends StatelessWidget {
  const OfficialBadge({super.key, this.label = 'Official'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_rounded,
            size: 11,
            color: AppColors.background,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppTheme.body(
              size: 10,
              weight: FontWeight.w800,
              color: AppColors.background,
            ),
          ),
        ],
      ),
    );
  }
}

/// The badge reduced to a checkmark, for use beside a name in a list.
class OfficialDot extends StatelessWidget {
  const OfficialDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.check_rounded,
        size: 11,
        color: AppColors.background,
      ),
    );
  }
}

/// The next-event stamp on a Discover row.
///
/// Navy and gold, matching the event rows on Events and the detail screen. A
/// pill washed in each organization's own colour turned the list into a
/// rainbow and left the label sitting on a dark tint of itself, which is the
/// worst case for a 10px weight-700 line.
class NextEventPill extends StatelessWidget {
  const NextEventPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.calendar_today_rounded,
            size: 11,
            color: AppColors.accent,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(
                size: 10,
                weight: FontWeight.w700,
                color: AppColors.bodyForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of "why we recommend this", marked with the recommender's sparkle.
class RecommendationReason extends StatelessWidget {
  const RecommendationReason({
    super.key,
    required this.text,
    this.maxLines = 1,
    this.color = AppColors.bodyForeground,
  });

  final String text;
  final int maxLines;

  /// The text colour; the sparkle stays gold. Lighter over photos.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 12,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              size: 11,
              weight: FontWeight.w700,
              color: color,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
