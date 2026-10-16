import 'package:flutter/foundation.dart';

import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/campus_event.dart';
import '../../data/repositories/events_repository.dart';
import '../../state/app_state.dart';
import 'event_filters.dart';

/// The state behind [EventsScreen]: which list is shown (all, my RSOs,
/// saved), the search and date filters, and the fetched lists.
class EventsViewModel extends ChangeNotifier {
  EventsViewModel({
    required EventsRepository events,
    required AppState appState,
    required Analytics analytics,
  }) : _repository = events,
       _appState = appState,
       _analytics = analytics,
       _membershipVersion = appState.membershipVersion {
    _appState.addListener(_onAppStateChanged);
  }

  final EventsRepository _repository;
  final AppState _appState;
  final Analytics _analytics;
  int _membershipVersion;
  bool _disposed = false;

  bool _joinedOnly = false;
  bool _savedOnly = false;
  EventDateFilter _dateFilter = EventDateFilter.any;
  String _query = '';

  /// Each list (all events, or only my RSOs') is fetched the first time it is
  /// shown, then kept.
  final Map<bool, List<CampusEvent>> _events = {};
  final Map<bool, String> _errors = {};

  bool get joinedOnly => _joinedOnly;
  bool get savedOnly => _savedOnly;
  EventDateFilter get dateFilter => _dateFilter;
  String get query => _query;

  /// The list for the selected chip, before filtering; `null` while loading.
  List<CampusEvent>? get events => _events[_joinedOnly];

  /// Every upcoming event, once fetched (for the "this week" banner).
  List<CampusEvent>? get allEvents => _events[false];

  String? get error => _errors[_joinedOnly];

  bool get ready =>
      _events.containsKey(_joinedOnly) || _errors.containsKey(_joinedOnly);

  bool get hasQueryOrDate =>
      _query.trim().isNotEmpty || _dateFilter != EventDateFilter.any;

  bool get hasFilters => hasQueryOrDate || _savedOnly;

  /// What the list shows: the selected list (or the saved events), narrowed
  /// by the search and the date filter. `null` while loading.
  List<CampusEvent>? visibleEvents(DateTime now) {
    final events = this.events;
    if (events == null) return null;
    final all = _events[false] ?? events;
    return filterEvents(
      events: _savedOnly
          ? all.where((event) => _appState.isEventSaved(event.id)).toList()
          : events,
      query: _query,
      dateFilter: _dateFilter,
      now: now,
    );
  }

  void start() => load(joinedOnly: false);

  Future<void> load({required bool joinedOnly}) async {
    _errors.remove(joinedOnly);
    notifyListeners();
    try {
      final events = await _repository.list(mine: joinedOnly);
      if (_disposed) return;
      _events[joinedOnly] = events;
    } on ApiException catch (e) {
      if (_disposed) return;
      _analytics.error(e, screen: Screens.events);
      _errors[joinedOnly] = e.message;
    }
    notifyListeners();
  }

  Future<void> reload() => load(joinedOnly: _joinedOnly);

  /// After a check-in: every list may show it, so all are fetched again.
  void reloadAll() {
    _events.clear();
    load(joinedOnly: _joinedOnly);
  }

  void select({required bool joinedOnly}) {
    _joinedOnly = joinedOnly;
    _savedOnly = false;
    notifyListeners();
    if (!_events.containsKey(joinedOnly)) load(joinedOnly: joinedOnly);
  }

  void showSaved() {
    _savedOnly = true;
    _joinedOnly = false;
    notifyListeners();
    if (!_events.containsKey(false)) load(joinedOnly: false);
  }

  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }

  void setDateFilter(EventDateFilter filter) {
    _dateFilter = filter;
    notifyListeners();
  }

  /// Clears the search and the date filter.
  void clearQueryAndDate() {
    _query = '';
    _dateFilter = EventDateFilter.any;
    notifyListeners();
  }

  /// Clears every filter, the saved-only view included.
  void clearFilters() {
    _savedOnly = false;
    clearQueryAndDate();
  }

  /// A group joined anywhere in the app adds its events to "My RSOs".
  void _onAppStateChanged() {
    if (_appState.membershipVersion == _membershipVersion) return;
    _membershipVersion = _appState.membershipVersion;
    _events.remove(true);
    if (_joinedOnly) load(joinedOnly: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _appState.removeListener(_onAppStateChanged);
    super.dispose();
  }
}
