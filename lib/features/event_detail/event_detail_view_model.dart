import 'package:flutter/foundation.dart';

import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/check_in.dart';
import '../../data/models/entry_point.dart';
import '../../data/models/schedule_block.dart';
import '../../data/repositories/events_repository.dart';
import '../../data/repositories/me_repository.dart';
import '../../state/app_state.dart';
import '../events/event_planning.dart';

/// The state behind [EventDetailScreen]: the full event, the classes it
/// clashes with and, for organizers, the venue's check-in QR code.
///
/// The event is fetched once per visit: the backend records each fetch as a
/// view, with [entryPoint] (and [recRequestId] for a "Free right now"
/// suggestion) saying how the student got here (BQ3).
class EventDetailViewModel extends ChangeNotifier {
  EventDetailViewModel({
    required this.eventId,
    required this.entryPoint,
    this.recRequestId,
    required EventsRepository events,
    required MeRepository me,
    required AppState appState,
    required Analytics analytics,
  }) : _events = events,
       _me = me,
       _appState = appState,
       _analytics = analytics;

  final int eventId;
  final EventEntryPoint entryPoint;
  final String? recRequestId;

  final EventsRepository _events;
  final MeRepository _me;
  final AppState _appState;
  final Analytics _analytics;
  bool _disposed = false;

  CampusEvent? _event;
  String? _error;
  CheckInCode? _organizerCode;
  List<ScheduleBlock>? _conflicts;

  /// The full event, once loaded.
  CampusEvent? get event => _event;
  String? get error => _error;
  bool get ready => _event != null || _error != null;

  /// The venue's QR code, when the student organizes the hosting group.
  CheckInCode? get organizerCode => _organizerCode;

  /// The student's classes at the same time; `null` until the schedule is
  /// known.
  List<ScheduleBlock>? get conflicts => _conflicts;

  Future<void> load() async {
    _error = null;
    notifyListeners();
    try {
      final event = await _events.detail(
        eventId,
        entryPoint: entryPoint,
        recRequestId: recRequestId,
      );
      if (_disposed) return;
      _event = event;
      notifyListeners();
      _loadOrganizerCode(event);
      _loadScheduleConflicts(event);
    } on ApiException catch (e) {
      if (_disposed) return;
      _analytics.error(e, screen: Screens.eventDetail);
      _error = e.message;
      notifyListeners();
    }
  }

  /// After a successful check-in from this event.
  void markCheckedIn() {
    final event = _event;
    if (event == null) return;
    _event = event.copyWith(checkedIn: true);
    notifyListeners();
  }

  /// Only the group's admins may show the QR code, and the app can't tell
  /// them apart from other members, so it asks: admins get the code, everyone
  /// else a refusal, which just means no button. Not logged as analytics.
  Future<void> _loadOrganizerCode(CampusEvent event) async {
    if (event.isCancelled || !_appState.isMemberOf(event.rsoId)) return;
    try {
      final code = await _events.checkInCode(event.id);
      if (_disposed) return;
      _organizerCode = code;
      notifyListeners();
    } on ApiException {
      // Not an organizer.
    }
  }

  Future<void> _loadScheduleConflicts(CampusEvent event) async {
    try {
      final schedule = await _me.schedule();
      if (_disposed) return;
      _conflicts = conflictingClasses(event, schedule);
    } on ApiException {
      if (_disposed) return;
      _conflicts = const [];
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
