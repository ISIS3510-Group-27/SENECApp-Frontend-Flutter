import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/check_in.dart';
import '../../state/app_state.dart';
import '../shell/track_screen.dart';

/// Checks the student in by scanning the event's QR code (the camera) and,
/// when they allow location, confirming they're near the venue (the GPS).
///
/// Opened from an event's page, it only accepts that event's code. Opened
/// from the Events tab ([event] is null), it accepts any event's code.
/// Pops with the [CheckInResult] once the backend accepts the check-in.
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key, this.event});

  final CampusEvent? event;

  static Route<CheckInResult> route({CampusEvent? event}) =>
      MaterialPageRoute<CheckInResult>(
        builder: (_) => CheckInScreen(event: event),
      );

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final _manualCode = TextEditingController();

  bool _typing = false;
  bool _submitting = false;

  /// Shown under the camera when a scan can't be used, e.g. a QR code that
  /// isn't a SENECApp one. Scanning carries on.
  String? _hint;

  /// The backend turned the check-in down; scanning stops until "Scan again".
  String? _refusal;

  CheckInResult? _result;

  @override
  void dispose() {
    _manualCode.dispose();
    super.dispose();
  }

  void _onScanned(String raw) {
    if (_submitting || _result != null || _refusal != null) return;
    final payload = CheckInPayload.tryParse(raw);
    final expected = widget.event?.id;
    if (payload == null) {
      setState(() => _hint = "That isn't a SENECApp check-in code.");
    } else if (expected != null && payload.eventId != expected) {
      setState(() => _hint = 'That code is for a different event.');
    } else {
      _submit(payload.eventId, payload.code);
    }
  }

  void _onTyped() {
    final code = _manualCode.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    _submit(widget.event!.id, code);
  }

  Future<void> _submit(int eventId, String code) async {
    final services = context.read<AppServices>();
    final appState = context.read<AppState>();
    setState(() {
      _submitting = true;
      _hint = null;
    });

    // The position only goes along with the student's consent. Without it,
    // the code alone checks them in.
    double? latitude;
    double? longitude;
    if (appState.student.locationOptIn) {
      final fix = await services.location.current();
      latitude = fix.latitude;
      longitude = fix.longitude;
    }

    try {
      final result = await services.events.checkIn(
        eventId,
        code: code,
        latitude: latitude,
        longitude: longitude,
      );
      if (!mounted) return;
      setState(() => _result = result);
      appState.refreshAttendance();
    } on ApiException catch (e) {
      if (!mounted) return;
      // A refusal (wrong code, too early, too far) is the check-in working as
      // intended; only failures to reach the backend are errors.
      final status = e.statusCode;
      if (status == null || status >= 500) {
        reportError(context, e, screen: Screens.checkInScanner);
      }
      setState(() => _refusal = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _scanAgain() => setState(() {
    _refusal = null;
    _hint = null;
  });

  @override
  Widget build(BuildContext context) =>
      TrackScreen(name: Screens.checkInScanner, child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    final event = widget.event;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 12, kPageGutter, 24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  size: 36,
                  iconSize: 17,
                  onPressed: () => Navigator.of(context).pop(_result),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Check in', style: AppTheme.heading(size: 20)),
                      Text(
                        event?.title ?? 'Scan the code at any event',
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
            const SizedBox(height: 24),
            if (_result case final result?)
              _Success(
                result: result,
                onDone: () => Navigator.of(context).pop(result),
              )
            else if (_refusal case final refusal?)
              _Refused(message: refusal, onRetry: _scanAgain)
            else ...[
              _Viewfinder(
                busy: _submitting,
                camera: _submitting
                    ? null
                    : context.read<AppServices>().qrCamera(context, _onScanned),
              ),
              const SizedBox(height: 14),
              Text(
                _hint ??
                    'Point your camera at the QR code the organizers '
                        'are showing.',
                textAlign: TextAlign.center,
                style: AppTheme.body(
                  size: 13,
                  height: 1.4,
                  weight: _hint == null ? FontWeight.w400 : FontWeight.w700,
                  color: _hint == null
                      ? AppColors.bodyForeground
                      : AppColors.accent,
                ),
              ),
              // Typing needs to know the event, so it's only offered from an
              // event's page.
              if (event != null) ...[
                const SizedBox(height: 20),
                if (_typing) ...[
                  const SectionLabel(text: 'Check-in code'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _manualCode,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _onTyped(),
                    style: AppTheme.body(size: 16, weight: FontWeight.w700),
                    decoration: const InputDecoration(
                      hintText: 'The code under the QR',
                    ),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Check in',
                    busy: _submitting,
                    onPressed: _onTyped,
                  ),
                ] else
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _typing = true),
                      child: Text(
                        'Type the code instead',
                        style: AppTheme.body(
                          size: 13,
                          weight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The square camera window with a gold frame, or a spinner while the
/// check-in is being sent.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.busy, required this.camera});

  final bool busy;
  final Widget? camera;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.hero),
          border: Border.all(color: AppColors.accent, width: 2),
        ),
        child: busy || camera == null
            ? const Center(
                child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.accent,
                  ),
                ),
              )
            : camera,
      ),
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.result, required this.onDone});

  final CheckInResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final distance = result.distanceM;

    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: AppColors.teal.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppRadius.hero),
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 44,
            color: AppColors.teal,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          result.alreadyCheckedIn
              ? 'You were already checked in'
              : "You're checked in!",
          textAlign: TextAlign.center,
          style: AppTheme.heading(size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          distance == null
              ? 'Enjoy the event.'
              : 'Confirmed ${distance.round()} m from the venue. Enjoy the '
                    'event.',
          textAlign: TextAlign.center,
          style: AppTheme.body(size: 13, color: AppColors.bodyForeground),
        ),
        const SizedBox(height: 28),
        PrimaryButton(label: 'Done', onPressed: onDone),
      ],
    );
  }
}

class _Refused extends StatelessWidget {
  const _Refused({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const Icon(
          Icons.error_outline_rounded,
          size: 48,
          color: AppColors.accent,
        ),
        const SizedBox(height: 16),
        Text(
          "Couldn't check you in",
          textAlign: TextAlign.center,
          style: AppTheme.heading(size: 20),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTheme.body(size: 13, color: AppColors.bodyForeground),
        ),
        const SizedBox(height: 28),
        PrimaryButton(label: 'Scan again', onPressed: onRetry),
      ],
    );
  }
}
