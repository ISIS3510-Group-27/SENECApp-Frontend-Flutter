import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/location/location_service.dart';
import '../../data/models/entry_point.dart';
import '../../data/models/free_now.dart';
import '../../state/app_state.dart';
import '../event_detail/event_detail_screen.dart';
import '../schedule/schedule_screen.dart';
import '../shell/track_screen.dart';

/// "I have a gap between classes, what's on nearby?"
///
/// The context-aware feature: the backend combines the student's class
/// schedule (their current or next free block), the time of day and where
/// they are (the phone's GPS when they allow it, else the building of their
/// last or next class) into events that fit.
class FreeNowScreen extends StatefulWidget {
  const FreeNowScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const FreeNowScreen());

  @override
  State<FreeNowScreen> createState() => _FreeNowScreenState();
}

class _FreeNowScreenState extends State<FreeNowScreen> {
  /// Asking before using location, until the student answers.
  late bool _askingConsent = !context.read<AppState>().student.locationOptIn;

  FreeNowSuggestions? _result;
  String? _error;
  bool _loading = false;

  /// Why GPS wasn't used this time, if the student allowed it.
  LocationProblem? _locationProblem;

  @override
  void initState() {
    super.initState();
    if (!_askingConsent) _load();
  }

  /// Reads the position (if allowed) and asks for suggestions. Each call is
  /// logged as the suggestions being shown, so it only runs on open, on
  /// refresh and after the student changes something that affects it.
  Future<void> _load() async {
    final services = context.read<AppServices>();
    final optedIn = context.read<AppState>().student.locationOptIn;
    setState(() {
      _askingConsent = false;
      _loading = true;
      _error = null;
    });

    LocationResult? fix;
    if (optedIn) fix = await services.location.current();
    if (!mounted) return;

    try {
      final result = await services.recommendations.freeNow(
        latitude: fix?.latitude,
        longitude: fix?.longitude,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _locationProblem = fix?.problem;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      reportError(context, e, screen: Screens.freeNow);
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _allowLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().setLocationOptIn(true);
    } on ApiException catch (e) {
      if (mounted) reportError(context, e, screen: Screens.freeNow);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    await _load();
  }

  Future<void> _openSchedule() async {
    await Navigator.of(context).push(ScheduleScreen.route());
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => TrackScreen(
    name: Screens.freeNow,
    ready: _askingConsent || _result != null || _error != null,
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) {
    final result = _result;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.accent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              kPageGutter,
              12,
              kPageGutter,
              kNavBarClearance,
            ),
            children: [
              const _Header(),
              const SizedBox(height: 20),
              if (_askingConsent)
                _ConsentCard(onAllow: _allowLocation, onSkip: _load)
              else if (result == null)
                _error == null
                    ? const LoadingBlock()
                    : ErrorBlock(message: _error!, onRetry: _load)
              else ...[
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: AppColors.accent,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                _FreeBlockBanner(result: result),
                const SizedBox(height: 14),
                _LocationLine(
                  result: result,
                  optedIn: context.select<AppState, bool>(
                    (s) => s.student.locationOptIn,
                  ),
                  problem: _locationProblem,
                  onAllow: _allowLocation,
                  onRetry: _load,
                ),
                if (!result.scheduleKnown) ...[
                  const SizedBox(height: 14),
                  _Notice(
                    text:
                        "Add your classes so we know when you're free. Until "
                        'then we assume the next two hours.',
                    action: 'Add schedule',
                    onAction: _openSchedule,
                  ),
                ],
                const SizedBox(height: 24),
                if (result.items.isEmpty)
                  _NothingFits(result: result)
                else ...[
                  SectionLabel(
                    text:
                        '${result.items.length} '
                        'event${result.items.length == 1 ? '' : 's'} fit',
                  ),
                  const SizedBox(height: 12),
                  for (final suggestion in result.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SuggestionCard(
                        suggestion: suggestion,
                        onTap: () => Navigator.of(context).push(
                          EventDetailScreen.route(
                            suggestion.event.id,
                            entryPoint: EventEntryPoint.freeNow,
                            recRequestId: result.requestId,
                            preview: suggestion.event,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
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
              Text('Free right now', style: AppTheme.heading(size: 20)),
              Text(
                'Events that fit the gap before your next class.',
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
    );
  }
}

/// Asked once, before the phone's location is ever read.
class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.onAllow, required this.onSkip});

  final VoidCallback onAllow;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TintedIconTile(
            icon: Icons.my_location_rounded,
            color: AppColors.accent,
          ),
          const SizedBox(height: 14),
          Text('Use your location?', style: AppTheme.heading(size: 18)),
          const SizedBox(height: 6),
          Text(
            "We'll suggest events you can walk to before your next class. "
            'Only the nearest campus building is saved, never your exact '
            'position. You can turn this off in Profile.',
            style: AppTheme.body(
              size: 13,
              height: 1.5,
              color: AppColors.bodyForeground,
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Use my location', onPressed: onAllow),
          const SizedBox(height: 10),
          PrimaryButton.secondary(
            label: 'Not now, use my schedule',
            onPressed: onSkip,
          ),
        ],
      ),
    );
  }
}

/// The free block, in the same gradient as the Events week banner.
class _FreeBlockBanner extends StatelessWidget {
  const _FreeBlockBanner({required this.result});

  final FreeNowSuggestions result;

  @override
  Widget build(BuildContext context) {
    final (overline, title, subtitle) = switch (result) {
      FreeNowSuggestions(:final freeFrom?, :final freeUntil?)
          when freeFrom.isAfter(DateTime.now()) =>
        (
          'NEXT FREE BLOCK',
          '${Dates.time(freeFrom)} - ${Dates.time(freeUntil)}',
          '${result.freeMinutes} min between classes',
        ),
      FreeNowSuggestions(:final freeUntil?) => (
        'FREE NOW',
        'Until ${Dates.time(freeUntil)}',
        '${result.freeMinutes} min before your next class',
      ),
      _ => (
        'NO FREE TIME',
        result.message ?? 'No more free time between classes today.',
        null,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.hero),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.orange],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            overline,
            style: AppTheme.body(
              size: 11,
              weight: FontWeight.w800,
              color: AppColors.accent,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: AppTheme.heading(
              size: 20,
              height: 1.25,
              color: Colors.white,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: AppTheme.body(
                size: 12,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Where the suggestions are measured from, and how to make that better.
class _LocationLine extends StatelessWidget {
  const _LocationLine({
    required this.result,
    required this.optedIn,
    required this.problem,
    required this.onAllow,
    required this.onRetry,
  });

  final FreeNowSuggestions result;
  final bool optedIn;
  final LocationProblem? problem;
  final VoidCallback onAllow;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final building = result.buildingName;
    final where = switch (result.locationSource) {
      LocationSource.gps when building != null => 'Near $building',
      LocationSource.gps => "You're off campus",
      LocationSource.schedule => 'Near $building, from your class schedule',
      LocationSource.none => "We don't know where you are",
    };

    final (
      String? why,
      String? action,
      VoidCallback? onAction,
    ) = switch (problem) {
      _ when !optedIn => (null, 'Use my location', onAllow),
      null => (null, null, null),
      LocationProblem.denied => (
        'Location permission was denied.',
        'Try again',
        onRetry,
      ),
      LocationProblem.unavailable => (
        "Couldn't get your location.",
        'Try again',
        onRetry,
      ),
      LocationProblem.deniedForever || LocationProblem.serviceOff => (
        problem == LocationProblem.serviceOff
            ? 'Location is off on this phone.'
            : 'Location is blocked for SENECApp.',
        'Open settings',
        () => context.read<AppServices>().location.openSettings(problem!),
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            result.locationSource == LocationSource.gps
                ? Icons.my_location_rounded
                : Icons.location_on_outlined,
            size: 16,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            [where, ?why].join('. '),
            style: AppTheme.body(size: 13, color: AppColors.bodyForeground),
          ),
        ),
        if (action != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                action,
                style: AppTheme.body(
                  size: 13,
                  weight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: AppTheme.body(
              size: 12,
              height: 1.5,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: onAction,
            child: Text(
              action,
              style: AppTheme.body(
                size: 13,
                weight: FontWeight.w800,
                color: AppColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion, required this.onTap});

  final EventSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final event = suggestion.event;
    final started = event.startsAt.isBefore(DateTime.now());

    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TintedIconTile(icon: Icons.event_rounded, color: event.color),
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
                const SizedBox(height: 6),
                Text(
                  '${started ? 'Happening now' : event.time} · '
                  '${event.location}',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
                for (final reason in suggestion.reasons) ...[
                  const SizedBox(height: 4),
                  RecommendationReason(text: reason),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
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

class _NothingFits extends StatelessWidget {
  const _NothingFits({required this.result});

  final FreeNowSuggestions result;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(
            Icons.event_available_rounded,
            size: 40,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(height: 12),
          Text('Nothing fits right now', style: AppTheme.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            result.hasFreeTime
                ? 'No events start during this free block. Pull down to check '
                      'again later.'
                : 'Check back tomorrow, or browse every event on the Events '
                      'tab.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
