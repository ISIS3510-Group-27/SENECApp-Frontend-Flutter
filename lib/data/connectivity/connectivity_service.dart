import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether the phone has a network (Wi-Fi, mobile data, ethernet), and when
/// that changes.
///
/// Having a network doesn't guarantee reaching the backend (a captive portal,
/// a server down); requests that fail anyway are handled where they're made.
/// This is the early signal: it lets screens say "you're offline" before the
/// student waits for a request to fail.
abstract interface class ConnectivityService {
  Future<bool> isConnected();

  /// `true` when a network appears, `false` when the last one goes.
  Stream<bool> get changes;
}

/// [ConnectivityService] on top of the `connectivity_plus` plugin.
class PlusConnectivityService implements ConnectivityService {
  PlusConnectivityService([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> isConnected() async =>
      _hasNetwork(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_hasNetwork).distinct();

  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}

/// Always connected: tests, unless they cut the connection on purpose.
class AlwaysConnected implements ConnectivityService {
  const AlwaysConnected();

  @override
  Future<bool> isConnected() async => true;

  @override
  Stream<bool> get changes => const Stream.empty();
}
