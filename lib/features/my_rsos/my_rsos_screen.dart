import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/assets/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/org_image.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/rso.dart';
import '../../state/app_state.dart';
import '../rso_detail/rso_detail_screen.dart';

/// The student's own memberships, with a semester summary on top.
class MyRsosScreen extends StatelessWidget {
  const MyRsosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final joined = state.joinedRsos;

    return ListView(
      padding: const EdgeInsets.only(bottom: kNavBarClearance),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
          child: _Header(
            overline: 'MY ORGANIZATIONS',
            title: 'My RSOs',
            mascot: BrandAssets.mascot67,
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: StatTile(
                  value: '${state.joinedCount}',
                  label: 'Joined',
                  color: AppColors.primary,
                ),
              ),
              Expanded(
                child: StatTile(
                  value: '${state.eventsAttended}',
                  label: 'Events attended',
                  color: AppColors.accent,
                ),
              ),
              Expanded(
                child: StatTile(
                  value: state.currentTerm,
                  label: 'This semester',
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: kPageGutter),
          child: SectionLabel(text: 'Active Memberships'),
        ),
        const SizedBox(height: 12),
        if (joined.isEmpty)
          const _NoMemberships()
        else
          for (final rso in joined)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kPageGutter,
                0,
                kPageGutter,
                12,
              ),
              child: _MembershipCard(
                rso: rso,
                onTap: () =>
                    Navigator.of(context).push(RsoDetailScreen.route(rso.id)),
              ),
            ),
      ],
    );
  }
}

/// The shared page header for My RSOs and Profile: overline, title, mascot.
class _Header extends StatelessWidget {
  const _Header({
    required this.overline,
    required this.title,
    required this.mascot,
  });

  final String overline;
  final String title;
  final String mascot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                overline,
                style: AppTheme.body(
                  size: 11,
                  weight: FontWeight.w700,
                  color: AppColors.mutedForeground,
                  letterSpacing: 1.8,
                ),
              ),
              Text(title, style: AppTheme.heading(size: 24)),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Image.asset(mascot, width: 56, height: 56, fit: BoxFit.cover),
        ),
      ],
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.rso, required this.onTap});

  final Rso rso;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      clipContents: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 96,
            child: Stack(
              fit: StackFit.expand,
              children: [
                OrgImage(rso: rso, iconSize: 30),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        rso.color.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      'Member',
                      style: AppTheme.body(size: 10, weight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rso.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.heading(size: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${rso.members} members',
                        style: AppTheme.body(
                          size: 12,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (rso.nextEventDate case final next?) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Next event',
                          style: AppTheme.body(
                            size: 10,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                        Text(
                          next,
                          style: AppTheme.body(
                            size: 10,
                            weight: FontWeight.w800,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoMemberships extends StatelessWidget {
  const _NoMemberships();

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
            Icons.groups_outlined,
            size: 40,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(height: 12),
          Text('No memberships yet', style: AppTheme.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            'Head to Discover and join your first organization.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
