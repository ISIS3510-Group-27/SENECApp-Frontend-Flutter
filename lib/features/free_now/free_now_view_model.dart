import 'package:flutter/foundation.dart';

import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/location/location_service.dart';
import '../../data/models/free_now.dart';
import '../../data/repositories/recommendations_repository.dart';
import '../../state/app_state.dart';

/// The state behind [FreeNowScreen]: location consent, the phone's position
/// and the suggestions the backend ranks for the current free block.
class FreeNowViewModel extends ChangeNotifier {
  FreeNowViewModel({
    required RecommendationsRepository recommendations,
    required LocationService location,
    required AppState appState,
    required Analytics analytics,
    bool Function()? isOnline,
  }) : _recommendations = recommendations,
       _location = location,
       _appState = appState,
       _analytics = analytics,
       _isOnline = isOnline ?? _alwaysOnline,
       _askingConsent = !appState.student.locationOptIn;

  static bool _alwaysOnline() => true;

  final RecommendationsRepository _recommendations;
  final LocationService _location;
  final AppState _appState;
  final Analytics _analytics;
  final bool Function() _isOnline;
  bool _disposed = false;

  bool _askingConsent;
  FreeNowSuggestions? _result;
  String? _error;
  bool _loading = false;
  LocationProblem? _locationProblem;
  bool _needsConnection = false;

  /// Asking before using location, until the student answers.
  bool get askingConsent => _askingConsent;

  FreeNowSuggestions? get result => _result;
  String? get error => _error;
  bool get loading => _loading;

  /// Why GPS wasn't used this time, if the student allowed it.
  LocationProblem? get locationProblem => _locationProblem;

  /// Suggestions are ranked live (free block, time, position), so there is
  /// no saved copy: offline, the screen says so instead of loading.
  bool get needsConnection => _needsConnection;

  bool get ready =>
      _askingConsent || _result != null || _error != null || _needsConnection;

  /// Loads right away unless the student still has to answer the consent
  /// question.
  void start() {
    if (!_askingConsent) load();
  }

  /// Reads the position (if allowed) and asks for suggestions. Each call is
  /// logged as the suggestions being shown, so it only runs on open, on
  /// refresh and after the student changes something that affects it.
  Future<void> load() async {
    final optedIn = _appState.student.locationOptIn;
    _askingConsent = false;
    _needsConnection = !_isOnline();
    if (_needsConnection) {
      // No point reading the GPS for a request that can't be sent.
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();

    LocationResult? fix;
    if (optedIn) fix = await _location.current();
    if (_disposed) return;

    try {
      final result = await _recommendations.freeNow(
        latitude: fix?.latitude,
        longitude: fix?.longitude,
      );
      if (_disposed) return;
      _result = result;
      _locationProblem = fix?.problem;
    } on ApiException catch (e) {
      if (_disposed) return;
      _analytics.error(e, screen: Screens.freeNow);
      _error = e.message;
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Stores the consent on the backend, then loads with the position.
  ///
  /// Returns the message to show when the consent couldn't be saved.
  Future<String?> allowLocation() async {
    try {
      await _appState.setLocationOptIn(true);
    } on ApiException catch (e) {
      if (!_disposed) _analytics.error(e, screen: Screens.freeNow);
      return e.message;
    }
    await load();
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
