import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// A push notification from the backend: its inbox entry and what it's about.
@immutable
class PushNotification {
  const PushNotification({
    this.notificationId,
    this.groupId,
    this.eventId,
    this.title,
    this.body,
  });

  /// Reads FCM's `data` (every value a string), plus the shown title and body.
  factory PushNotification.fromData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) => PushNotification(
    notificationId: int.tryParse('${data['notification_id']}'),
    groupId: int.tryParse('${data['group_id']}'),
    eventId: int.tryParse('${data['event_id']}'),
    title: title,
    body: body,
  );

  /// The inbox entry: opening the push opens it (BQ8).
  final int? notificationId;

  final int? groupId;
  final int? eventId;
  final String? title;
  final String? body;
}

/// Push notifications through Firebase Cloud Messaging.
abstract interface class PushService {
  /// Whether pushes can arrive at all (Firebase configured).
  bool get enabled;

  /// Asks to show notifications (Android 13+), then returns this phone's
  /// token, or null when the student says no or pushes are unavailable.
  Future<String?> token();

  /// A new token, when FCM rotates it.
  Stream<String> get tokenRefreshes;

  /// The push the app was launched from, if any.
  Future<PushNotification?> launchedFrom();

  /// Pushes tapped while the app was in the background.
  Stream<PushNotification> get taps;

  /// Pushes arriving while the app is open; the system doesn't show those.
  Stream<PushNotification> get arrivals;
}

/// No pushes: Firebase isn't configured (local development).
class DisabledPushService implements PushService {
  const DisabledPushService();

  @override
  bool get enabled => false;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Future<PushNotification?> launchedFrom() async => null;

  @override
  Stream<PushNotification> get taps => const Stream.empty();

  @override
  Stream<PushNotification> get arrivals => const Stream.empty();
}

/// [PushService] on `firebase_messaging`. Needs `Firebase.initializeApp()`.
class FirebasePushService implements PushService {
  FirebasePushService([FirebaseMessaging? messaging])
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  bool get enabled => true;

  @override
  Future<String?> token() async {
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return null;
      }
      return await _messaging.getToken();
    } on Exception {
      // No Play Services, offline at launch...: no pushes this time.
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Future<PushNotification?> launchedFrom() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _read(message);
  }

  @override
  Stream<PushNotification> get taps =>
      FirebaseMessaging.onMessageOpenedApp.map(_read);

  @override
  Stream<PushNotification> get arrivals =>
      FirebaseMessaging.onMessage.map(_read);

  static PushNotification _read(RemoteMessage message) =>
      PushNotification.fromData(
        message.data,
        title: message.notification?.title,
        body: message.notification?.body,
      );
}
