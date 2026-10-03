import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

abstract interface class ReminderNotifications {
  Future<bool> requestPermission();

  Future<void> schedule({
    required int eventId,
    required DateTime at,
    required String title,
    required String body,
  });

  Future<void> cancel(int eventId);

  Stream<int> get taps;

  Future<int?> launchedFrom();
}

class DisabledReminderNotifications implements ReminderNotifications {
  const DisabledReminderNotifications();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule({
    required int eventId,
    required DateTime at,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel(int eventId) async {}

  @override
  Stream<int> get taps => const Stream.empty();

  @override
  Future<int?> launchedFrom() async => null;
}

class LocalReminderNotifications implements ReminderNotifications {
  LocalReminderNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<int>.broadcast();
  Future<void>? _ready;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'leave_reminders',
      'Leave-time reminders',
      channelDescription: 'Tells you when to leave for a saved event',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> _init() => _ready ??= () async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = int.tryParse(response.payload ?? '');
        if (id != null) _taps.add(id);
      },
    );
  }();

  @override
  Future<bool> requestPermission() async {
    await _init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> schedule({
    required int eventId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    await _init();
    await _plugin.zonedSchedule(
      eventId,
      title,
      body,
      tz.TZDateTime.from(at, tz.UTC),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: '$eventId',
    );
  }

  @override
  Future<void> cancel(int eventId) async {
    await _init();
    await _plugin.cancel(eventId);
  }

  @override
  Stream<int> get taps {
    unawaited(_init());
    return _taps.stream;
  }

  @override
  Future<int?> launchedFrom() async {
    await _init();
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch == null || !launch.didNotificationLaunchApp) return null;
    return int.tryParse(launch.notificationResponse?.payload ?? '');
  }
}

ReminderNotifications platformReminders() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? LocalReminderNotifications()
    : const DisabledReminderNotifications();
