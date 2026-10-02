import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/rso_list_tile.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/entry_point.dart';
import '../../data/models/recommendation.dart';
import '../../state/app_state.dart';
import '../rso_detail/rso_detail_screen.dart';

/// Every group recommended on Discover, each with all its reasons.
///
/// Shows the list Discover already fetched rather than asking again: a new
/// request would be logged as a second, different set of recommendations
/// shown (BQ2).
class RecommendationsScreen extends StatelessWidget {
  const RecommendationsScreen({super.key, required this.recommendations});

  final GroupRecommendations recommendations;

  static Route<void> route(GroupRecommendations recommendations) =>
      MaterialPageRoute<void>(
        builder: (_) => RecommendationsScreen(recommendations: recommendations),
      );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // A group joined from here stops being a suggestion.
    final items = [
      for (final item in recommendations.items)
        if (!state.isMember(item.group)) item,
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: kNavBarClearance),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kPageGutter,
                12,
                kPageGutter,
                0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    size: 36,
                    iconSize: 17,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Recommended for you',
                          style: AppTheme.heading(size: 20),
                        ),
                        Text(
                          'Picked from your interests, your free time and '
                          'where you have classes.',
                          style: AppTheme.body(
                            size: 12,
                            height: 1.4,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kPageGutter,
                  vertical: 40,
                ),
                child: Text(
                  "You've joined every group we had in mind. Check back "
                  'soon!',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(
                    size: 13,
                    color: AppColors.mutedForeground,
                  ),
                ),
              )
            else
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kPageGutter,
                    0,
                    kPageGutter,
                    12,
                  ),
                  child: RsoListTile(
                    rso: item.group,
                    reasons: item.reasons,
                    saveSource: 'recommendations',
                    onTap: () => Navigator.of(context).push(
                      RsoDetailScreen.route(
                        item.group.id,
                        entryPoint: EntryPoint.recommendation,
                        recRequestId: recommendations.requestId,
                        preview: item.group,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
