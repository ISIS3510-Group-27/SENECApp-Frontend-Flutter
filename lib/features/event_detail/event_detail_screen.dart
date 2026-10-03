import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app_services.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/check_in.dart';
import '../../data/models/entry_point.dart';
import '../../state/app_state.dart';
import '../check_in/check_in_screen.dart';
import '../rso_detail/rso_detail_screen.dart';
import '../shell/track_screen.dart';

/// One event: when, where, who hosts it.
///
/// Fetched once per visit: the backend records each fetch as a view, with
/// [entryPoint] (and [recRequestId] for a "Free right now" suggestion) saying
/// how the student got here (BQ3).
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.eventId,
    required this.entryPoint,
    this.recRequestId,
    this.preview,
  });

  final int eventId;
  final EventEntryPoint entryPoint;
  final String? recRequestId;

  /// The card that was tapped, shown while the full event loads.
  final CampusEvent? preview;

  static Route<void> route(
    int eventId, {
    required EventEntryPoint entryPoint,
    String? recRequestId,
    CampusEvent? preview,
  }) => MaterialPageRoute<void>(
    builder: (_) => EventDetailScreen(
      eventId: eventId,
      entryPoint: entryPoint,
      recRequestId: recRequestId,
      preview: preview,
    ),
  );

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  CampusEvent? _event;
  String? _error;

  /// The venue's QR code, when the student organizes the hosting group.
  CheckInCode? _organizerCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final event = await context.read<AppServices>().events.detail(
        widget.eventId,
        entryPoint: widget.entryPoint,
        recRequestId: widget.recRequestId,
      );
      if (!mounted) return;
      setState(() => _event = event);
      _loadOrganizerCode(event);
    } on ApiException catch (e) {
      if (!mounted) return;
      reportError(context, e, screen: Screens.eventDetail);
      setState(() => _error = e.message);
    }
  }

  /// Only the group's admins may show the QR code, and the app can't tell
  /// them apart from other members, so it asks: admins get the code, everyone
  /// else a refusal, which just means no button. Not logged as analytics.
  Future<void> _loadOrganizerCode(CampusEvent event) async {
    if (event.isCancelled ||
        !context.read<AppState>().isMemberOf(event.rsoId)) {
      return;
    }
    try {
      final code = await context.read<AppServices>().events.checkInCode(
        event.id,
      );
      if (mounted) setState(() => _organizerCode = code);
    } on ApiException {
      // Not an organizer.
    }
  }

  Future<void> _checkIn(CampusEvent event) async {
    final result = await Navigator.of(
      context,
    ).push(CheckInScreen.route(event: event));
    if (result != null && mounted) {
      setState(() => _event = event.copyWith(checkedIn: true));
    }
  }

  @override
  Widget build(BuildContext context) => TrackScreen(
    name: Screens.eventDetail,
    ready: _event != null || _error != null,
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) {
    final event = _event ?? widget.preview;

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
            if (event == null)
              _error == null
                  ? const LoadingBlock()
                  : ErrorBlock(message: _error!, onRetry: _load)
            else ...[
              const SizedBox(height: 20),
              _Heading(event: event),
              const SizedBox(height: 20),
              _InfoRow(icon: Icons.calendar_today_rounded, text: event.date),
              _InfoRow(icon: Icons.schedule_rounded, text: event.timeRange),
              _InfoRow(icon: Icons.location_on_outlined, text: event.location),
              if (event.attendeeCount case final count?)
                _InfoRow(
                  icon: Icons.people_outline_rounded,
                  text: event.capacity == null
                      ? '$count checked in'
                      : '$count of ${event.capacity} checked in',
                ),
              // Check-in needs the full event; the preview may be stale.
              if (_event != null)
                _CheckInSection(
                  event: event,
                  now: DateTime.now(),
                  onCheckIn: () => _checkIn(event),
                ),
              if (_organizerCode case final code?) ...[
                const SizedBox(height: 10),
                PrimaryButton.secondary(
                  label: 'Show check-in QR',
                  onPressed: () => _OrganizerQrSheet.show(context, event, code),
                ),
              ],
              if (event.description case final description?) ...[
                const SizedBox(height: 12),
                SectionLabel(text: 'About'),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: AppTheme.body(
                    size: 14,
                    height: 1.55,
                    color: AppColors.bodyForeground,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SectionLabel(text: 'Hosted by'),
              const SizedBox(height: 10),
              AppCard(
                onTap: () => Navigator.of(context).push(
                  RsoDetailScreen.route(
                    event.rsoId,
                    entryPoint: EntryPoint.event,
                  ),
                ),
                child: Row(
                  children: [
                    TintedIconTile(
                      icon: Icons.groups_rounded,
                      color: event.color,
                      size: 40,
                      iconSize: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        event.rsoName,
                        style: AppTheme.heading(size: 14),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.mutedForeground,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.event});

  final CampusEvent event;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.rsoName.toUpperCase(),
          style: AppTheme.body(
            size: 11,
            weight: FontWeight.w800,
            color: event.color,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(event.title, style: AppTheme.heading(size: 24, height: 1.2)),
        if (event.isCancelled || event.checkedIn) ...[
          const SizedBox(height: 10),
          _StatusPill(
            icon: event.isCancelled
                ? Icons.event_busy_rounded
                : Icons.check_circle_rounded,
            text: event.isCancelled ? 'Cancelled' : 'You checked in',
            color: event.isCancelled ? AppColors.primary : AppColors.teal,
          ),
        ],
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.foreground),
          const SizedBox(width: 5),
          Text(text, style: AppTheme.body(size: 11, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          TintedIconTile(
            icon: icon,
            color: AppColors.accent,
            size: 36,
            iconSize: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(size: 14, color: AppColors.bodyForeground),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Check in with QR" while check-in is open; otherwise when it opens, or
/// that it closed. Nothing once the student is in, or for a cancelled event.
class _CheckInSection extends StatelessWidget {
  const _CheckInSection({
    required this.event,
    required this.now,
    required this.onCheckIn,
  });

  final CampusEvent event;
  final DateTime now;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    if (event.isCancelled || event.checkedIn) return const SizedBox.shrink();

    if (event.checkInOpenAt(now)) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: PrimaryButton(label: 'Check in with QR', onPressed: onCheckIn),
      );
    }

    final opens = event.startsAt.subtract(CampusEvent.checkInOpensBefore);
    final sameDay = DateUtils.isSameDay(opens.toLocal(), now.toLocal());
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          const Icon(
            Icons.qr_code_2_rounded,
            size: 16,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              now.isBefore(opens)
                  ? 'Check-in opens at ${Dates.time(opens)}'
                        '${sameDay ? '' : ' on ${Dates.day(opens)}'}.'
                  : 'Check-in for this event has closed.',
              style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}

/// The QR code an organizer holds up at the venue, with the code in text for
/// anyone whose camera won't scan.
class _OrganizerQrSheet extends StatelessWidget {
  const _OrganizerQrSheet({required this.event, required this.code});

  final CampusEvent event;
  final CheckInCode code;

  static Future<void> show(
    BuildContext context,
    CampusEvent event,
    CheckInCode code,
  ) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.hero)),
    ),
    builder: (_) => _OrganizerQrSheet(event: event, code: code),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageGutter, 24, kPageGutter, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Check-in code', style: AppTheme.heading(size: 20)),
          const SizedBox(height: 4),
          Text(
            event.title,
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
          ),
          const SizedBox(height: 20),
          // Dark modules on white: scanners need the contrast.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: QrImageView(
              data: code.qrPayload,
              size: 220,
              semanticsLabel: 'Check-in QR code for ${event.title}',
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            code.code,
            style: AppTheme.heading(size: 24, letterSpacing: 4),
          ),
          const SizedBox(height: 6),
          Text(
            'Attendees scan this from the event page in SENECApp.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
