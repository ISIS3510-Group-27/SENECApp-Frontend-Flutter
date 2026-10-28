import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/connectivity/connectivity_service.dart';

/// The app's view of the connection, for every screen.
///
/// Screens read [online] to adapt before acting (warn instead of sending a
/// join that can't arrive), and listen to [reconnected] to refresh what they
/// showed from the phone's copy once the network is back.
class ConnectionStatus extends ChangeNotifier {
  ConnectionStatus(this._service);

  final ConnectivityService _service;
  StreamSubscription<bool>? _subscription;
  final _reconnected = StreamController<void>.broadcast();

  bool _online = true;
  DateTime? _offlineSince;

  /// Optimistic until the first check answers: a fresh start is usually
  /// online, and requests that fail still fall back to the phone's copy.
  bool get online => _online;

  /// When the connection was lost, for "offline since 10:42".
  DateTime? get offlineSince => _offlineSince;

  /// Fires once each time the network comes back.
  Stream<void> get reconnected => _reconnected.stream;

  void start() {
    _subscription ??= _service.changes.listen(_set);
    _service.isConnected().then(_set, onError: (Object _) {});
  }

  void _set(bool online) {
    if (online == _online) return;
    _online = online;
    _offlineSince = online ? null : DateTime.now();
    notifyListeners();
    if (online) _reconnected.add(null);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _reconnected.close();
    super.dispose();
  }
}
