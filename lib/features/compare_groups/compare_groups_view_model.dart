import 'package:flutter/foundation.dart';

import '../../data/api/api_client.dart';
import '../../data/local/local_store.dart';
import '../../data/local/recommendation_snapshot_store.dart';
import '../../data/models/recommendation.dart';
import '../../data/repositories/recommendations_repository.dart';

/// One recommendation response and the two groups being compared.
///
/// The groups and request ID always come from the same response. Selection
/// changes are local: only opening or refreshing the comparison should load.
class CompareGroupsViewModel extends ChangeNotifier {
  CompareGroupsViewModel({
    required RecommendationsRepository recommendations,
    required int Function() sessionVersion,
    RecommendationSnapshotStore? snapshots,
    bool Function()? isOnline,
  }) : _recommendations = recommendations,
       _sessionVersion = sessionVersion,
       _ownerSession = sessionVersion(),
       _snapshots = snapshots,
       _isOnline = isOnline ?? _alwaysOnline;

  static bool _alwaysOnline() => true;

  final RecommendationsRepository _recommendations;
  final RecommendationSnapshotStore? _snapshots;
  final bool Function() _isOnline;

  /// Pass the current OfflineCache.sessionVersion, which changes even when
  /// the same account signs out and back in during a pending request.
  final int Function() _sessionVersion;
  final int _ownerSession;
  bool _disposed = false;
  bool _loading = false;
  Future<void>? _inFlight;
  GroupRecommendations? _result;
  String? _error;
  Object? _failure;
  bool _fromCache = false;
  DateTime? _savedAt;
  int? _firstId;
  int? _secondId;

  bool get _active => !_disposed && _sessionVersion() == _ownerSession;

  GroupRecommendations? get result => _active && !_expired ? _result : null;
  bool get _expired => _fromCache && !(_snapshots?.isFresh(_savedAt!) ?? false);
  List<GroupRecommendation> get items => result?.items ?? const [];
  bool get loading => _active && _loading;
  String? get error => !_active
      ? null
      : _expired
      ? 'Saved recommendations have expired. Connect and try again.'
      : _error;
  Object? get failure => _active ? _failure : null;
  bool get fromCache => _active && _fromCache && !_expired;
  DateTime? get savedAt => fromCache ? _savedAt : null;
  bool get ready => _active && (result != null || error != null);
  bool get hasEnoughGroups => items.length >= 2;

  GroupRecommendation? get first => _selected(_firstId);
  GroupRecommendation? get second => _selected(_secondId);
  bool get canCompare => first != null && second != null;

  /// Reuse this response's requestId when opening a recommendation's detail.
  bool get canOpenGroup =>
      _active &&
      !_fromCache &&
      _isOnline() &&
      !_loading &&
      _error == null &&
      (_result?.requestId.isNotEmpty ?? false);

  /// Repeated calls share one request, including calls from a load listener.
  Future<void> load() {
    if (!_active) return Future<void>.value();
    final pending = _inFlight;
    if (pending != null) return pending;

    _loading = true;
    _error = null;
    _failure = null;
    final operation = Future<void>.sync(_fetch);
    final tracked = operation.whenComplete(() {
      _inFlight = null;
      if (_active) {
        _loading = false;
        notifyListeners();
      }
    });
    _inFlight = tracked;
    notifyListeners();
    return tracked;
  }

  Future<void> _fetch() async {
    // Begin the optional disk read alongside the network request. Storage
    // errors are contained by read(); a slow disk never delays live results.
    final saved =
        _snapshots?.read() ?? Future<Cached<GroupRecommendations>?>.value();
    try {
      if (!_isOnline()) {
        throw const ApiException(null, 'Connect to load recommendations.');
      }
      final response = await _recommendations.groups();
      if (!_active) return;
      _apply(response);
      if (_active) await _snapshots?.write(response);
    } on ApiException catch (e) {
      if (!_active) return;
      if (e.isUnreachable) {
        final cached = await saved;
        if (!_active) return;
        if (cached != null && (_snapshots?.isFresh(cached.savedAt) ?? false)) {
          _apply(cached.value, savedAt: cached.savedAt);
          return;
        }
      }
      if (_active) _fail(e, e.message);
    } on Exception catch (e) {
      if (_active) _fail(e, 'Could not load recommendations. Try again.');
    }
  }

  void _apply(GroupRecommendations response, {DateTime? savedAt}) {
    final seen = <int>{};
    _fromCache = savedAt != null;
    _savedAt = savedAt;
    _result = GroupRecommendations(
      requestId: _fromCache ? '' : response.requestId,
      modelVersion: response.modelVersion,
      items: List.unmodifiable([
        for (final item in response.items)
          if (seen.add(item.group.id)) item,
      ]),
    );
    if (_selected(_firstId) == null) _firstId = null;
    if (_selected(_secondId) == null) _secondId = null;
  }

  /// A reconnection during an offline disk read must still fetch live data.
  Future<void> refreshAfterReconnect() async {
    final pending = _inFlight;
    if (pending != null) {
      await pending;
      if (!_fromCache && _error == null && _result != null) return;
    }
    if (_active && _isOnline()) await load();
  }

  void _fail(Object failure, String message) {
    // An old response must not remain actionable after a failed refresh.
    _result = null;
    _fromCache = false;
    _savedAt = null;
    _error = message;
    _failure = failure;
  }

  GroupRecommendation? _selected(int? id) {
    if (id == null) return null;
    for (final item in items) {
      if (item.group.id == id) return item;
    }
    return null;
  }

  void selectFirst(int? id) => _select(id, first: true);
  void selectSecond(int? id) => _select(id, first: false);

  void _select(int? id, {required bool first}) {
    if (!_active || _loading) return;
    if (id != null &&
        (_selected(id) == null || id == (first ? _secondId : _firstId))) {
      return;
    }
    if (id == (first ? _firstId : _secondId)) return;
    if (first) {
      _firstId = id;
    } else {
      _secondId = id;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _result = null;
    super.dispose();
  }
}
