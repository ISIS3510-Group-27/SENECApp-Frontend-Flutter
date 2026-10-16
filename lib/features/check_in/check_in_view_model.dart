import 'package:flutter/foundation.dart';

import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/location/location_service.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/check_in.dart';
import '../../data/repositories/events_repository.dart';

/// The state behind [CheckInScreen]: validating what the camera scanned,
/// adding the GPS position when the student allows it, and the backend's
/// answer.
///
/// Opened for one [event], it only accepts that event's code; without one it
/// accepts any event's code.
class CheckInViewModel extends ChangeNotifier {
  CheckInViewModel({
    this.event,
    required EventsRepository events,
    required LocationService location,
    required bool Function() locationOptIn,
    required VoidCallback onCheckedIn,
    required Analytics analytics,
  }) : _events = events,
       _location = location,
       _locationOptIn = locationOptIn,
       _onCheckedIn = onCheckedIn,
       _analytics = analytics;

  final CampusEvent? event;

  final EventsRepository _events;
  final LocationService _location;

  /// Read when a code is sent: the student may allow location meanwhile.
  final bool Function() _locationOptIn;

  /// Tells the rest of the app (attendance in `AppState`) about a check-in.
  final VoidCallback _onCheckedIn;
  final Analytics _analytics;
  bool _disposed = false;

  bool _submitting = false;
  String? _hint;
  String? _refusal;
  CheckInResult? _result;

  bool get submitting => _submitting;

  /// Shown under the camera when a scan can't be used, e.g. a QR code that
  /// isn't a SENECApp one. Scanning carries on.
  String? get hint => _hint;

  /// The backend turned the check-in down; scanning stops until [scanAgain].
  String? get refusal => _refusal;

  /// The accepted check-in.
  CheckInResult? get result => _result;

  /// Whether the camera should be scanning.
  bool get scanning => !_submitting && _result == null && _refusal == null;

  void onScanned(String raw) {
    if (!scanning) return;
    final payload = CheckInPayload.tryParse(raw);
    final expected = event?.id;
    if (payload == null) {
      _hint = "That isn't a SENECApp check-in code.";
      notifyListeners();
    } else if (expected != null && payload.eventId != expected) {
      _hint = 'That code is for a different event.';
      notifyListeners();
    } else {
      submit(payload.eventId, payload.code);
    }
  }

  /// A code typed by hand, for [event] (the camera can't read the screen).
  void submitTyped(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty || event == null) return;
    submit(event!.id, trimmed);
  }

  Future<void> submit(int eventId, String code) async {
    _submitting = true;
    _hint = null;
    notifyListeners();

    // The position only goes along with the student's consent. Without it,
    // the code alone checks them in.
    double? latitude;
    double? longitude;
    if (_locationOptIn()) {
      final fix = await _location.current();
      latitude = fix.latitude;
      longitude = fix.longitude;
    }

    try {
      final result = await _events.checkIn(
        eventId,
        code: code,
        latitude: latitude,
        longitude: longitude,
      );
      if (_disposed) return;
      _result = result;
      _onCheckedIn();
    } on ApiException catch (e) {
      if (_disposed) return;
      // A refusal (wrong code, too early, too far) is the check-in working as
      // intended; only failures to reach the backend are errors.
      final status = e.statusCode;
      if (status == null || status >= 500) {
        _analytics.error(e, screen: Screens.checkInScanner);
      }
      _refusal = e.message;
    } finally {
      if (!_disposed) {
        _submitting = false;
        notifyListeners();
      }
    }
  }

  void scanAgain() {
    _refusal = null;
    _hint = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
