import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/entry_point.dart';
import '../event_detail/event_detail_screen.dart';
import 'event_planning.dart';

class EventItineraryScreen extends StatelessWidget {
  const EventItineraryScreen({
    super.key,
    required this.savedEvents,
    this.now = DateTime.now,
  });

  final List<CampusEvent> savedEvents;
  final DateTime Function() now;

  static Route<void> route(List<CampusEvent> savedEvents) =>
      MaterialPageRoute<void>(
        builder: (_) => EventItineraryScreen(savedEvents: savedEvents),
      );

  @override
  Widget build(BuildContext context) {
    final selected = buildEventItinerary(savedEvents, now: now());
    final selectedIds = selected.map((event) => event.id).toSet();
    final skipped = savedEvents
        .where((event) => !selectedIds.contains(event.id))
        .toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            kPageGutter,
            12,
            kPageGutter,
            kNavBarClearance,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: RoundIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                size: 36,
                iconSize: 17,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Saved itinerary', style: AppTheme.heading(size: 24)),
            const SizedBox(height: 6),
            Text(
              'Built from saved future events to maximize full events without overlaps.',
              style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
            ),
            const SizedBox(height: 20),
            if (selected.isEmpty)
              const _EmptyItinerary()
            else ...[
              SectionLabel(text: '${selected.length} event plan'),
              const SizedBox(height: 10),
              for (final event in selected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ItineraryCard(event: event, included: true),
                ),
            ],
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 14),
              SectionLabel(text: 'Not included'),
              const SizedBox(height: 10),
              for (final event in skipped)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ItineraryCard(event: event, included: false),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              'Travel time and class conflicts are shown separately on event details.',
              style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItineraryCard extends StatelessWidget {
  const _ItineraryCard({required this.event, required this.included});

  final CampusEvent event;
  final bool included;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.of(context).push(
        EventDetailScreen.route(
          event.id,
          entryPoint: EventEntryPoint.events,
          preview: event,
        ),
      ),
      border: included
          ? AppColors.accent.withValues(alpha: 0.35)
          : AppColors.border,
      child: Row(
        children: [
          TintedIconTile(
            icon: included
                ? Icons.event_available_rounded
                : Icons.event_busy_rounded,
            color: included ? AppColors.accent : AppColors.mutedForeground,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: AppTheme.heading(size: 14)),
                const SizedBox(height: 3),
                Text(
                  event.rsoName,
                  style: AppTheme.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: event.color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${event.date} · ${event.timeRange}',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.mutedForeground,
          ),
        ],
      ),
    );
  }
}

class _EmptyItinerary extends StatelessWidget {
  const _EmptyItinerary();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          const Icon(
            Icons.event_note_rounded,
            size: 36,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(height: 10),
          Text('No future saved events', style: AppTheme.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            'Save upcoming events first, then generate a plan here.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
