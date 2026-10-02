import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api/api_client.dart';
import '../../data/models/rso.dart';
import '../../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'badges.dart';
import 'org_image.dart';
import 'surfaces.dart';

/// One organization in a list: Discover's results, or the recommendations.
///
/// The heart is a nested tap target, so it stops the tap from also opening the
/// detail screen - saving and opening are different intents.
class RsoListTile extends StatelessWidget {
  const RsoListTile({
    super.key,
    required this.rso,
    required this.onTap,
    this.saveSource = 'explore',
    this.reasons = const [],
  });

  final Rso rso;
  final VoidCallback onTap;

  /// The screen a save is recorded from. Saves from Explore are the ones
  /// BQ13 counts.
  final String saveSource;

  /// Why the recommender picked this group, listed under its name.
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    final liked = context.select<AppState, bool>((s) => s.isSaved(rso));

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: SizedBox(
              width: 56,
              height: 56,
              child: OrgImage(rso: rso, iconSize: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        rso.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.heading(size: 14),
                      ),
                    ),
                    if (rso.verified) ...[
                      const SizedBox(width: 6),
                      const OfficialDot(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${rso.members} members · ${rso.category.label}',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
                for (final reason in reasons) ...[
                  const SizedBox(height: 6),
                  RecommendationReason(text: reason, maxLines: 2),
                ],
                if (rso.nextEvent case final nextEvent?) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: NextEventPill(label: nextEvent),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _LikeButton(rso: rso, liked: liked, source: saveSource),
        ],
      ),
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.rso,
    required this.liked,
    required this.source,
  });

  final Rso rso;
  final bool liked;
  final String source;

  Future<void> _toggle(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().toggleSave(rso, source: source);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: liked ? 'Remove ${rso.name} from saved' : 'Save ${rso.name}',
      button: true,
      child: Material(
        color: liked ? AppColors.primary.wash : AppColors.secondary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _toggle(context),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 16,
              color: liked ? AppColors.primary : AppColors.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}
