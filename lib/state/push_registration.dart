import 'dart:async';

import '../data/api/api_client.dart';
import '../data/push/push_service.dart';
import '../data/repositories/notifications_repository.dart';

/// Keeps the backend's record of where to push the signed-in student's
/// notifications: this phone's token, registered after sign-in and whenever
/// FCM rotates it, removed on sign-out.
class PushRegistration {
  PushRegistration({
    required PushService push,
    required NotificationsRepository notifications,
    String? platform,
  }) : _push = push,
       _notifications = notifications,
       // The backend only stores these two.
       _platform = platform == 'android' || platform == 'ios' ? platform : null;

  final PushService _push;
  final NotificationsRepository _notifications;
  final String? _platform;

  String? _token;
  StreamSubscription<String>? _refreshes;

  /// The token the backend has for this phone, if any.
  String? get token => _token;

  /// Registers this phone. Failures are not the student's problem: they
  /// just get no pushes until the next sign-in.
  Future<void> register() async {
    if (!_push.enabled) return;
    final token = await _push.token();
    if (token == null) return;
    await _send(token);
    _refreshes ??= _push.tokenRefreshes.listen(_send);
  }

  /// Unregisters this phone. Call while still signed in: the request needs
  /// the student's token.
  Future<void> unregister() async {
    // Nothing to wait for: no more refreshes will be handled either way.
    unawaited(_refreshes?.cancel());
    _refreshes = null;
    final token = _token;
    _token = null;
    if (token == null) return;
    try {
      await _notifications.unregisterDevice(token);
    } on ApiException {
      // The backend drops tokens FCM reports as dead.
    }
  }

  Future<void> _send(String token) async {
    try {
      await _notifications.registerDevice(token, platform: _platform);
      _token = token;
    } on ApiException {
      // Tried again on the next sign-in or token refresh.
    }
  }
}
