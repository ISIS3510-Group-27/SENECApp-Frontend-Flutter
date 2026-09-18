import 'package:flutter/foundation.dart';

import '../data/models/app_notification.dart';
import '../data/models/campus_event.dart';
import '../data/models/rso.dart';
import '../data/models/rso_category.dart';
import '../data/models/student_profile.dart';
import '../data/repositories/rso_repository.dart';

/// Everything the user changes while the app is open.
///
/// The repository holds the catalogue, which never changes; this holds the
/// student's relationship to it - what they joined, liked and read. Keeping the
/// two apart means the screens can stay stateless and a membership toggled on
/// one screen is immediately visible on all the others.
///
/// State lives in memory only: it resets on restart. Persisting it is a later
/// sprint's job, and it belongs behind the repository when that happens.
class AppState extends ChangeNotifier {
  AppState({RsoRepository repository = const RsoRepository()})
    : _repository = repository,
      _membershipIds = {...RsoRepository.seedMembershipIds},
      _readNotificationIds = {...RsoRepository.seedReadNotificationIds};

  final RsoRepository _repository;
  final Set<int> _membershipIds;
  final Set<int> _readNotificationIds;
  final Set<int> _likedIds = {};

  // --- Catalogue passthrough ----------------------------------------------

  StudentProfile get student => _repository.currentStudent();

  List<Rso> get featured => _repository.featured();

  List<AppNotification> get notifications => _repository.allNotifications();

  Rso rsoById(int id) => _repository.byId(id);

  List<CampusEvent> eventsForRso(int rsoId) => _repository.eventsFor(rsoId);

  List<Rso> discover({
    RsoCategory category = RsoCategory.all,
    String query = '',
  }) => _repository.search(category: category, query: query);

  // --- Memberships ---------------------------------------------------------

  bool hasJoined(int rsoId) => _membershipIds.contains(rsoId);

  List<Rso> get joinedRsos => _repository
      .allRsos()
      .where((r) => _membershipIds.contains(r.id))
      .toList();

  int get joinedCount => _membershipIds.length;

  int get eventsAttended => RsoRepository.eventsAttended;

  String get currentTerm => RsoRepository.currentTerm;

  /// Joining is one-way in this prototype: the detail CTA turns into a
  /// confirmation rather than a "Leave" button, matching the Figma flow.
  void join(int rsoId) {
    if (_membershipIds.add(rsoId)) notifyListeners();
  }

  // --- Likes ---------------------------------------------------------------

  bool hasLiked(int rsoId) => _likedIds.contains(rsoId);

  void toggleLike(int rsoId) {
    if (!_likedIds.remove(rsoId)) _likedIds.add(rsoId);
    notifyListeners();
  }

  // --- Events --------------------------------------------------------------

  /// All upcoming events, or only those hosted by organizations the student
  /// belongs to.
  List<CampusEvent> events({required bool joinedOnly}) {
    final all = _repository.allEvents();
    if (!joinedOnly) return all;
    return all.where((e) => _membershipIds.contains(e.rsoId)).toList();
  }

  // --- Notifications -------------------------------------------------------

  bool isUnread(int notificationId) =>
      !_readNotificationIds.contains(notificationId);

  int get unreadCount => notifications.where((n) => isUnread(n.id)).length;

  void markRead(int notificationId) {
    if (_readNotificationIds.add(notificationId)) notifyListeners();
  }

  void markAllRead() {
    final before = _readNotificationIds.length;
    _readNotificationIds.addAll(notifications.map((n) => n.id));
    if (_readNotificationIds.length != before) notifyListeners();
  }
}
