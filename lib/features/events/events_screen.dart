import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/api/api_client.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/entry_point.dart';
import '../../state/app_state.dart';
import '../check_in/check_in_screen.dart';
import '../event_detail/event_detail_screen.dart';
import '../free_now/free_now_screen.dart';

/// Every upcoming event, filterable down to the student's own
///  organizations.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key, this.clock = DateTime.now});

  /// For the "this week" banner.
  final DateTime Function() clock;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  bool _joinedOnly = false;

  /// Each list is fetched the first time it is shown, then kept.
  final Map<bool, List<CampusEvent>> _events = {};
  final Map<bool, String> _errors = {};

  late final AppState _appState = context.read<AppState>();
  late int _membershipVersion = _appState.membershipVersion;

  @override
  void initState() {
    super.initState();
    _load(joinedOnly: false);
    _appState.addListener(_onAppStateChanged);
  }

  @override
  void dispose() {
    _appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  /// A group joined anywhere in the app adds its events to "My RSOs".
  void _onAppStateChanged() {
    if (_appState.membershipVersion == _membershipVersion) return;
    _membershipVersion = _appState.membershipVersion;
    _events.remove(true);
    if (_joinedOnly) _load(joinedOnly: true);
  }

  Future<void> _load({required bool joinedOnly}) async {
    setState(() => _errors.remove(joinedOnly));
    try {
      final events = await context.read<AppServices>().events.list(
        mine: joinedOnly,
      );
      if (mounted) setState(() => _events[joinedOnly] = events);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errors[joinedOnly] = e.message);
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push(CheckInScreen.route());
    // Checked in from here: refresh so the event shows it.
    if (result != null && mounted) {
      _events.clear();
      _load(joinedOnly: _joinedOnly);
    }
  }

  void _select({required bool joinedOnly}) {
    setState(() => _joinedOnly = joinedOnly);
    if (!_events.containsKey(joinedOnly)) _load(joinedOnly: joinedOnly);
  }

  @override
  Widget build(BuildContext context) {
    final events = _events[_joinedOnly];
    final error = _errors[_joinedOnly];

    return RefreshIndicator(
      onRefresh: () => _load(joinedOnly: _joinedOnly),
      color: AppColors.accent,
      child: ListView(
        padding: const EdgeInsets.only(bottom: kNavBarClearance),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
            child: Row(
              children: [
                Expanded(
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
                // At the venue, straight to the camera without finding the
                // event first.
                RoundIconButton(
                  icon: Icons.qr_code_scanner_rounded,
                  tooltip: 'Scan check-in code',
                  onPressed: _scan,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: kPageGutter),
            child: _FreeNowCard(),
          ),
          if (_events[false] case final all?) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
              child: _WeekBanner(events: all, now: widget.clock()),
            ),
          ],
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
            child: Row(
              spacing: 8,
              children: [
                SelectableChip.filter(
                  label: 'All Events',
                  selected: !_joinedOnly,
                  onSelected: (_) => _select(joinedOnly: false),
                ),
                SelectableChip.filter(
                  label: 'My RSOs',
                  selected: _joinedOnly,
                  onSelected: (_) => _select(joinedOnly: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (error != null)
            ErrorBlock(
              message: error,
              onRetry: () => _load(joinedOnly: _joinedOnly),
            )
          else if (events == null)
            const LoadingBlock()
          else if (events.isEmpty)
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
                  onTap: () => Navigator.of(context).push(
                    EventDetailScreen.route(
                      event.id,
                      entryPoint: EventEntryPoint.events,
                      preview: event,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// The week-at-a-glance hero. Its more of a banner than a card due to the
/// colors merged.
class _WeekBanner extends StatelessWidget {
  const _WeekBanner({required this.events, required this.now});

  final List<CampusEvent> events;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final weekEnd = DateTime(now.year, now.month, now.day + 7);
    final count = events.where((e) => e.startsAt.isBefore(weekEnd)).length;

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
                  Dates.range(now, weekEnd.subtract(const Duration(days: 1))),
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
                if (event.isCancelled) ...[
                  const SizedBox(height: 3),
                  const _MetaLine(
                    icon: Icons.event_busy_rounded,
                    text: 'Cancelled',
                  ),
                ],
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

/// The way into "Free right now": what's on in the gap before the next class.
class _FreeNowCard extends StatelessWidget {
  const _FreeNowCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.of(context).push(FreeNowScreen.route()),
      border: AppColors.accent.withValues(alpha: 0.35),
      child: Row(
        children: [
          const TintedIconTile(
            icon: Icons.near_me_rounded,
            color: AppColors.accent,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Free right now?', style: AppTheme.heading(size: 15)),
                const SizedBox(height: 2),
                Text(
                  'Events nearby that fit before your next class',
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
