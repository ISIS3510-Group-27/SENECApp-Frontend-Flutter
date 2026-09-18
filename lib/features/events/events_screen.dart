import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/campus_event.dart';
import '../../data/repositories/rso_repository.dart';
import '../../state/app_state.dart';
import '../rso_detail/rso_detail_screen.dart';

/// Every upcoming event, filterable down to the student's own organizations.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  bool _joinedOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final events = state.events(joinedOnly: _joinedOnly);
    final weekCount = state.events(joinedOnly: false).length;

    return ListView(
      padding: const EdgeInsets.only(bottom: kNavBarClearance),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'UPCOMING',
                style: AppTheme.body(
                  size: 11,
                  weight: FontWeight.w700,
                  color: AppColors.mutedForeground,
                  letterSpacing: 1.8,
                ),
              ),
              Text(
                'SENECApp Events',
                style: AppTheme.heading(size: 24),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: _WeekBanner(count: weekCount),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: Row(
            spacing: 8,
            children: [
              SelectableChip.filter(
                label: 'All Events',
                selected: !_joinedOnly,
                onSelected: (_) => setState(() => _joinedOnly = false),
              ),
              SelectableChip.filter(
                label: 'My RSOs',
                selected: _joinedOnly,
                onSelected: (_) => setState(() => _joinedOnly = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (events.isEmpty)
          const _NoJoinedEvents()
        else
          for (final event in events)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kPageGutter,
                0,
                kPageGutter,
                12,
              ),
              child: _EventCard(
                event: event,
                onTap: () => Navigator.of(
                  context,
                ).push(RsoDetailScreen.route(event.rsoId)),
              ),
            ),
      ],
    );
  }
}

/// The week-at-a-glance hero. Its gradient is the only place brand red and the
/// warm orange meet, which is what makes it read as a banner rather than a card.
class _WeekBanner extends StatelessWidget {
  const _WeekBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.hero),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.orange],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -40,
              top: -50,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'THIS WEEK',
                  style: AppTheme.body(
                    size: 11,
                    weight: FontWeight.w800,
                    color: AppColors.accent,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count events from your\ncampus organizations',
                  style: AppTheme.heading(
                    size: 18,
                    height: 1.25,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  RsoRepository.eventsWeekRange,
                  style: AppTheme.body(
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});

  final CampusEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TintedIconTile(
            icon: Icons.calendar_today_rounded,
            color: AppColors.accent,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(event.title, style: AppTheme.heading(size: 14)),
                const SizedBox(height: 2),
                Text(
                  event.rsoName,
                  style: AppTheme.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: event.color,
                  ),
                ),
                const SizedBox(height: 8),
                _MetaLine(
                  icon: Icons.calendar_today_rounded,
                  text: '${event.date} · ${event.time}',
                ),
                const SizedBox(height: 3),
                _MetaLine(
                  icon: Icons.location_on_outlined,
                  text: event.location,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: AppColors.mutedForeground),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
          ),
        ),
      ],
    );
  }
}

class _NoJoinedEvents extends StatelessWidget {
  const _NoJoinedEvents();

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
            Icons.event_busy_rounded,
            size: 40,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(height: 12),
          Text('Nothing on your calendar', style: AppTheme.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            'Join an organization on Discover and its events show up here.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
