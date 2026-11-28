import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/connectivity/connectivity_service.dart';

/// The app's view of the connection, for every screen.
///
/// Screens read [online] to adapt before acting (warn instead of sending a
/// join that can't arrive), and listen to [reconnected] to refresh what they
/// showed from the phone's copy once the network is back.
class ConnectionStatus extends ChangeNotifier {
  /// [reachable], when given, checks that the backend really answers before
  /// [reconnected] fires: the phone reports a network a moment before requests
  /// get through, and reloads sent in that moment would fall back to the
  /// phone's copy again, with nothing left to retry them.
  ///
  /// [showingSavedCopy], when given, says whether any screen still shows the
  /// phone's copy. A reload can still fail right after a return (the first
  /// request on a network that just came back sometimes does), so if it does,
  /// [reconnected] fires again a little later, up to [staleRetries] times.
  ConnectionStatus(
    this._service, {
    Future<bool> Function()? reachable,
    bool Function()? showingSavedCopy,
  }) : _reachable = reachable,
       _showingSavedCopy = showingSavedCopy;

  final ConnectivityService _service;
  final Future<bool> Function()? _reachable;
  final bool Function()? _showingSavedCopy;
  StreamSubscription<bool>? _subscription;
  final _reconnected = StreamController<void>.broadcast();

  /// Waits between checks of the backend after the network returns; after the
  /// last one [reconnected] fires anyway, so screens still try.
  static const reachRetries = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  /// After a return, how long to wait before checking whether every screen
  /// got live data, and how many extra announcements to make if not.
  static const staleCheckAfter = Duration(seconds: 5);
  static const staleRetries = 2;

  bool _online = true;
  DateTime? _offlineSince;
  int _generation = 0;
  bool _disposed = false;
  Timer? _wait;

  /// Optimistic until the first check answers: a fresh start is usually
  /// online, and requests that fail still fall back to the phone's copy.
  bool get online => _online;

  /// When the connection was lost, for "offline since 10:42".
  DateTime? get offlineSince => _offlineSince;

  /// Fires once each time the network comes back (and the backend answers),
  /// and again if screens are still showing the phone's copy shortly after.
  Stream<void> get reconnected => _reconnected.stream;

  void start() {
    _subscription ??= _service.changes.listen(_set);
    _service.isConnected().then(_set, onError: (Object _) {});
  }

  void _set(bool online) {
    if (online == _online) return;
    _online = online;
    _offlineSince = online ? null : DateTime.now();
    _generation++;
    _wait?.cancel();
    notifyListeners();
    if (online) unawaited(_announce(_generation));
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  /// A wait that dispose cancels, so no timer outlives this object.
  Future<void> _sleep(Duration duration) {
    final done = Completer<void>();
    _wait = Timer(duration, done.complete);
    return done.future;
  }

  /// Fires [reconnected] once the backend answers, unless the connection is
  /// lost again (or this is disposed) in the meantime.
  Future<void> _announce(int generation) async {
    final reachable = _reachable;
    if (reachable != null) {
      for (final wait in [Duration.zero, ...reachRetries]) {
        if (wait > Duration.zero) await _sleep(wait);
        if (!_current(generation)) return;
        bool ok;
        try {
          ok = await reachable();
        } on Object {
          ok = false;
        }
        if (!_current(generation)) return;
        if (ok) break;
      }
    }
    if (!_current(generation)) return;
    _reconnected.add(null);

    final stale = _showingSavedCopy;
    if (stale == null) return;
    for (var i = 0; i < staleRetries; i++) {
      await _sleep(staleCheckAfter);
      if (!_current(generation) || !stale()) return;
      _reconnected.add(null);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _wait?.cancel();
    _subscription?.cancel();
    _reconnected.close();
    super.dispose();
  }
}
