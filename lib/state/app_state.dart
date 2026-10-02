import 'package:flutter/foundation.dart';

import '../data/api/api_client.dart';
import '../data/models/app_notification.dart';
import '../data/models/entry_point.dart';
import '../data/models/rso.dart';
import '../data/models/student_profile.dart';
import '../data/repositories/events_repository.dart';
import '../data/repositories/groups_repository.dart';
import '../data/repositories/me_repository.dart';
import '../data/repositories/notifications_repository.dart';

/// The signed-in student's relationship to the catalogue: what they joined,
/// saved and read.
///
/// Screens fetch the lists they show themselves; this holds what more than one
/// screen needs, so a group joined on one screen is a member on all the others
/// straight away. It is built when the student signs in and thrown away when
/// they sign out.
class AppState extends ChangeNotifier {
  AppState({
    required StudentProfile student,
    required MeRepository me,
    required GroupsRepository groups,
    required EventsRepository events,
    required NotificationsRepository notifications,
    DateTime Function() clock = DateTime.now,
  }) : _student = student,
       _me = me,
       _groups = groups,
       _events = events,
       _notificationsRepo = notifications,
       _clock = clock;

  StudentProfile _student;

  /// The signed-in student, from the backend's `GET /me`.
  StudentProfile get student => _student;

  final MeRepository _me;
  final GroupsRepository _groups;
  final EventsRepository _events;
  final NotificationsRepository _notificationsRepo;
  final DateTime Function() _clock;

  /// Fetches everything the shared screens need. Each part fails on its own,
  /// so a slow inbox doesn't hide the student's groups.
  Future<void> load() => Future.wait([
    refreshMemberships(),
    refreshNotifications(),
    refreshAttendance(),
  ]);

  // --- Profile -------------------------------------------------------------

  /// Allows (or stops) using the phone's location for suggestions. Throws
  /// [ApiException] if the backend refuses.
  Future<void> setLocationOptIn(bool optIn) async {
    _student = await _me.setLocationOptIn(optIn);
    notifyListeners();
  }

  // --- Memberships ---------------------------------------------------------

  List<Rso>? _myGroups;
  String? _myGroupsError;
  final Set<int> _memberIds = {};
  int _membershipVersion = 0;

  /// The student's groups, or `null` until the first load finishes.
  List<Rso>? get myGroups => _myGroups;

  String? get myGroupsError => _myGroupsError;

  int get joinedCount => _memberIds.length;

  /// Changes whenever the student joins a group, so screens listing "my"
  /// things know to fetch again.
  int get membershipVersion => _membershipVersion;

  /// Whether the student belongs to the group with [groupId], once their
  /// groups have loaded.
  bool isMemberOf(int groupId) => _memberIds.contains(groupId);

  bool isMember(Rso rso) =>
      _myGroups == null ? rso.isMember : _memberIds.contains(rso.id);

  Future<void> refreshMemberships() async {
    try {
      final mine = await _groups.mine();
      _myGroups = mine;
      _myGroupsError = null;
      _memberIds
        ..clear()
        ..addAll(mine.map((r) => r.id));
    } on ApiException catch (e) {
      _myGroupsError = e.message;
    }
    notifyListeners();
  }

  /// Joins [rso]. [entryPoint] is how the student reached its profile, and
  /// [recRequestId] the recommendation list it came from, if any.
  /// Throws [ApiException] if the backend refuses.
  Future<void> join(
    Rso rso, {
    required EntryPoint entryPoint,
    String? recRequestId,
    String? joinAttemptId,
    String? motivation,
  }) async {
    await _groups.join(
      rso.id,
      entryPoint: entryPoint,
      recRequestId: recRequestId,
      joinAttemptId: joinAttemptId,
      motivation: motivation,
    );
    _memberIds.add(rso.id);
    _membershipVersion++;
    notifyListeners();
    // The list behind My RSOs, with the new group first.
    await refreshMemberships();
  }

  // --- Saves ---------------------------------------------------------------

  final Map<int, bool> _saved = {};

  /// Saved state as last set on this device, else as the backend reported it
  /// when [rso] was fetched.
  bool isSaved(Rso rso) => _saved[rso.id] ?? rso.isSaved;

  /// Saves or unsaves [rso]. The heart flips at once and flips back if the
  /// backend refuses. [source] is the screen: `explore` or `group_detail`.
  Future<void> toggleSave(Rso rso, {required String source}) async {
    final save = !isSaved(rso);
    _saved[rso.id] = save;
    notifyListeners();
    try {
      if (save) {
        await _groups.save(rso.id, source: source);
      } else {
        await _groups.unsave(rso.id);
      }
    } on ApiException {
      _saved[rso.id] = !save;
      notifyListeners();
      rethrow;
    }
  }

  // --- Attendance ----------------------------------------------------------

  int? _eventsAttended;

  /// Events of the student's groups they checked in to this semester, or
  /// `null` until known.
  int? get eventsAttended => _eventsAttended;

  /// `Sem I` (January to June) or `Sem II` (July to December).
  String get currentTerm => _clock().month < 7 ? 'Sem I' : 'Sem II';

  DateTime get _termStart {
    final now = _clock();
    return DateTime(now.year, now.month < 7 ? 1 : 7);
  }

  Future<void> refreshAttendance() async {
    try {
      _eventsAttended = await _events.attendedSince(_termStart);
      notifyListeners();
    } on ApiException {
      // Stays unknown; the stat shows a dash.
    }
  }

  // --- Notifications -------------------------------------------------------

  List<AppNotification>? _notifications;
  String? _notificationsError;

  /// Newest first, or `null` until the first load finishes.
  List<AppNotification>? get notifications => _notifications;

  String? get notificationsError => _notificationsError;

  int get unreadCount => _notifications?.where((n) => n.unread).length ?? 0;

  Future<void> refreshNotifications() async {
    try {
      _notifications = await _notificationsRepo.list();
      _notificationsError = null;
    } on ApiException catch (e) {
      _notificationsError = e.message;
    }
    notifyListeners();
  }

  /// The student tapped [notification]. Recorded as an interaction (BQ8).
  Future<void> openNotification(AppNotification notification) async {
    if (notification.opened) return;
    _replaceNotification(notification.copyWith(opened: true));
    try {
      await _notificationsRepo.open(notification.id);
    } on ApiException {
      _replaceNotification(notification);
    }
  }

  /// Clears every unread notification without opening it. Recorded as
  /// dismissed, not opened, so BQ8 still sees them as ignored.
  Future<void> markAllRead() async {
    final unread = [...?_notifications?.where((n) => n.unread)];
    if (unread.isEmpty) return;
    for (final notification in unread) {
      _replaceNotification(
        notification.copyWith(dismissed: true),
        notify: false,
      );
    }
    notifyListeners();

    final results = await Future.wait([
      for (final notification in unread)
        _notificationsRepo
            .dismiss(notification.id)
            .then((_) => true, onError: (_) => false),
    ]);
    // Some didn't go through: show the inbox as the backend has it.
    if (results.contains(false)) await refreshNotifications();
  }

  void _replaceNotification(AppNotification updated, {bool notify = true}) {
    _notifications = [
      for (final n in _notifications ?? const <AppNotification>[])
        n.id == updated.id ? updated : n,
    ];
    if (notify) notifyListeners();
  }

  // --- Lifecycle -----------------------------------------------------------

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Requests can still be in flight when the student signs out and this state
  /// is dropped; their late results are ignored.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
