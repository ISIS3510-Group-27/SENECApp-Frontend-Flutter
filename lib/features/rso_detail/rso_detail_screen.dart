import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/org_image.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/rso.dart';
import '../../state/app_state.dart';

/// Level two of the hierarchy, and the deepest the app goes: from here the
/// student can join, which is the whole point of Discover.
class RsoDetailScreen extends StatelessWidget {
  const RsoDetailScreen({super.key, required this.rsoId});

  final int rsoId;

  /// Pushed onto whichever tab's navigator the student came from, which is what
  /// makes backing out return them to that tab.
  static Route<void> route(int rsoId) =>
      MaterialPageRoute<void>(builder: (_) => RsoDetailScreen(rsoId: rsoId));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rso = state.rsoById(rsoId);
    final events = state.eventsForRso(rsoId);
    final joined = state.hasJoined(rsoId);

    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              _Cover(rso: rso),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kPageGutter,
                  20,
                  kPageGutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatsRow(rso: rso),
                    const SizedBox(height: 20),
                    SectionLabel(text: 'About'),
                    const SizedBox(height: 8),
                    Text(
                      rso.description,
                      style: AppTheme.body(
                        size: 14,
                        color: AppColors.bodyForeground,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in rso.tags)
                          StaticChip.tinted(label: tag, color: rso.color),
                      ],
                    ),
                    if (events.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      SectionLabel(text: 'Upcoming Events'),
                      const SizedBox(height: 12),
                      for (final event in events) ...[
                        _DetailEventRow(event: event),
                        const SizedBox(height: 8),
                      ],
                    ],
                    const SizedBox(height: 12),
                    SectionLabel(text: 'Members'),
                    const SizedBox(height: 12),
                    _MemberStack(rso: rso),
                    // Clears the pinned CTA and the shell's navigation bar.
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _JoinCta(rso: rso, joined: joined),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.rso});

  final Rso rso;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 224,
      child: Stack(
        fit: StackFit.expand,
        children: [
          OrgImage(rso: rso, iconSize: 56),
          // Darkens the lower half so the name stays legible over any photo.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66080D28), Color(0xF2171A21)],
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: kPageGutter,
            child: RoundIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              background: AppColors.background.withValues(alpha: 0.6),
              size: 36,
              iconSize: 17,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          if (rso.verified)
            const Positioned(
              top: 18,
              right: kPageGutter,
              child: OfficialBadge(label: 'Official RSO'),
            ),
          Positioned(
            left: kPageGutter,
            right: kPageGutter,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rso.category.label.toUpperCase(),
                  style: AppTheme.body(
                    size: 11,
                    weight: FontWeight.w800,
                    color: AppColors.accent.withValues(alpha: 0.75),
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(rso.name, style: AppTheme.heading(size: 24, height: 1.15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.rso});

  final Rso rso;

  @override
  Widget build(BuildContext context) {
    // Events-per-semester and rating are display placeholders in this
    // prototype; they arrive with the backend.
    return Row(
      spacing: 12,
      children: [
        Expanded(
          child: StatTile(
            value: '${rso.members}',
            label: 'Members',
            color: rso.color,
          ),
        ),
        const Expanded(
          child: StatTile(
            value: '8',
            label: 'Events/sem',
            color: AppColors.accent,
          ),
        ),
        const Expanded(
          child: StatTile(value: '4.8', label: 'Rating', color: AppColors.teal),
        ),
      ],
    );
  }
}

class _DetailEventRow extends StatelessWidget {
  const _DetailEventRow({required this.event});

  final CampusEvent event;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      border: Colors.transparent,
      child: Row(
        children: [
          const TintedIconTile(
            icon: Icons.calendar_today_rounded,
            color: AppColors.accent,
            size: 40,
            iconSize: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.title,
                  style: AppTheme.body(size: 14, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${event.date} · ${event.time} · ${event.location}',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The overlapping avatar row. Initials stand in until member photos exist.
class _MemberStack extends StatelessWidget {
  const _MemberStack({required this.rso});

  final Rso rso;

  static const _initials = ['MR', 'JC', 'AP', 'DB', 'LG'];

  @override
  Widget build(BuildContext context) {
    final colors = [
      rso.color,
      AppColors.accent,
      AppColors.teal,
      AppColors.orange,
      AppColors.violet,
    ];

    const diameter = 36.0;
    const step = 28.0; // 8px of overlap between neighbours.

    return Row(
      children: [
        SizedBox(
          width: (_initials.length - 1) * step + diameter,
          height: diameter,
          child: Stack(
            // Painted back-to-front, so reversing puts the first avatar on top
            // and each one overlaps the avatar to its right.
            children: [
              for (final (index, initials)
                  in _initials.indexed.toList().reversed)
                Positioned(
                  left: index * step,
                  child: Container(
                    width: diameter,
                    height: diameter,
                    decoration: BoxDecoration(
                      color: colors[index],
                      shape: BoxShape.circle,
                      // Cuts this avatar out of the one behind it.
                      border: Border.all(color: AppColors.background, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initials,
                      style: AppTheme.body(
                        size: 11,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '+${rso.members - _initials.length} more',
          style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
        ),
      ],
    );
  }
}

class _JoinCta extends StatelessWidget {
  const _JoinCta({required this.rso, required this.joined});

  final Rso rso;
  final bool joined;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // Fades the list out behind the button instead of cutting it off.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            AppColors.background,
            AppColors.background,
            Colors.transparent,
          ],
          stops: [0, 0.7, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kPageGutter, 20, kPageGutter, 16),
        child: Material(
          color: joined ? AppColors.secondary : rso.color,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: joined
                ? null
                : () {
                    context.read<AppState>().join(rso.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Welcome to ${rso.name}!')),
                    );
                  },
            child: Container(
              width: double.infinity,
              height: 54,
              alignment: Alignment.center,
              child: Text(
                joined ? '✓ Joined - Welcome!' : 'Join RSO',
                style: AppTheme.heading(
                  size: 16,
                  weight: FontWeight.w700,
                  color: joined ? AppColors.mutedForeground : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
