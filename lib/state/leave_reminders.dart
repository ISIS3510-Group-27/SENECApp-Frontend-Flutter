import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/format/dates.dart';
import '../data/api/api_client.dart';
import '../data/location/location_service.dart';
import '../data/models/campus_event.dart';
import '../data/models/catalog.dart';
import '../data/models/schedule_block.dart';
import '../data/reminders/reminder_notifications.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/me_repository.dart';

@immutable
class ReminderEvent {
  const ReminderEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    this.buildingName,
    this.latitude,
    this.longitude,
  });

  factory ReminderEvent.of(CampusEvent event) => ReminderEvent(
    id: event.id,
    title: event.title,
    startsAt: event.startsAt,
    buildingName: event.buildingName,
    latitude: event.buildingLatitude,
    longitude: event.buildingLongitude,
  );

  factory ReminderEvent.fromJson(Map<String, dynamic> json) => ReminderEvent(
    id: json['id'] as int,
    title: json['title'] as String,
    startsAt: DateTime.parse(json['starts_at'] as String),
    buildingName: json['building_name'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
  );

  final int id;
  final String title;
  final DateTime startsAt;
  final String? buildingName;
  final double? latitude;
  final double? longitude;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'building_name': buildingName,
    'latitude': latitude,
    'longitude': longitude,
  };
}

enum LeaveOrigin { here, previousClass, unknown }

enum LeaveSkip { inClass, tooLate }

@immutable
class LeavePlan {
  const LeavePlan({
    required this.walkMinutes,
    required this.origin,
    this.notifyAt,
    this.afterClass = false,
    this.skip,
    this.blockingClass,
  });

  final int walkMinutes;
  final LeaveOrigin origin;

  final DateTime? notifyAt;

  final bool afterClass;
  final LeaveSkip? skip;

  final ScheduleBlock? blockingClass;
}

const walkingMetersPerMinute = 80.0;
const leaveBuffer = Duration(minutes: 5);
const unknownWalk = Duration(minutes: 10);

const gpsHorizon = Duration(hours: 3);

const _bogotaOffset = Duration(hours: 5);

LeavePlan planLeave({
  required ReminderEvent event,
  required List<ScheduleBlock> schedule,
  required Map<int, Building> buildings,
  required DateTime now,
  ({double latitude, double longitude})? here,
}) {
  final start = event.startsAt.toUtc();
  final wall = start.subtract(_bogotaOffset);
  final day = DateTime.utc(wall.year, wall.month, wall.day);
  final classes = [
    for (final block in schedule)
      if (block.weekday == wall.weekday - 1)
        (
          block: block,
          start: _at(day, block.start),
          end: _at(day, block.end),
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));

  for (final c in classes) {
    if (!c.start.isAfter(start) && c.end.isAfter(start)) {
      return LeavePlan(
        walkMinutes: 0,
        origin: LeaveOrigin.unknown,
        skip: LeaveSkip.inClass,
        blockingClass: c.block,
      );
    }
  }

  double? meters;
  var origin = LeaveOrigin.unknown;
  final target = (event.latitude, event.longitude);
  if (target case (final double lat, final double lng)) {
    if (here != null && start.difference(now) <= gpsHorizon) {
      meters = _distance(here.latitude, here.longitude, lat, lng);
      origin = LeaveOrigin.here;
    } else {
      final before = classes.where((c) => !c.end.isAfter(start)).toList();
      final building = before.isEmpty
          ? null
          : buildings[before.last.block.buildingId];
      if (building?.latitude case final double fromLat) {
        meters = _distance(fromLat, building!.longitude!, lat, lng);
        origin = LeaveOrigin.previousClass;
      }
    }
  }

  final walk = meters == null
      ? unknownWalk
      : Duration(minutes: meters < 100 ? 0 : math.max(1, (meters / walkingMetersPerMinute).round()));
  var notifyAt = start.subtract(walk).subtract(leaveBuffer);
  var afterClass = false;
  for (final c in classes) {
    if (!c.start.isAfter(notifyAt) && c.end.isAfter(notifyAt)) {
      notifyAt = c.end;
      afterClass = true;
    }
  }

  if (!notifyAt.isAfter(now)) {
    return LeavePlan(
      walkMinutes: walk.inMinutes,
      origin: origin,
      skip: LeaveSkip.tooLate,
    );
  }
  return LeavePlan(
    walkMinutes: walk.inMinutes,
    origin: origin,
    notifyAt: notifyAt,
    afterClass: afterClass,
  );
}

({String title, String body}) leaveMessage(ReminderEvent event, LeavePlan plan) {
  final place = event.buildingName ?? 'the venue';
  final walk = plan.walkMinutes == 0
      ? "You're right next to $place"
      : '${plan.walkMinutes} min walk to $place';
  return (
    title: plan.afterClass
        ? 'Class is over: head to ${event.title}'
        : 'Time to leave for ${event.title}',
    body: '$walk · starts at ${Dates.time(event.startsAt)}',
  );
}

DateTime _at(DateTime bogotaDay, TimeOfDay time) => bogotaDay
    .add(Duration(hours: time.hour, minutes: time.minute))
    .add(_bogotaOffset);

double _distance(double lat1, double lon1, double lat2, double lon2) {
  const radius = 6371000.0;
  double rad(double degrees) => degrees * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * radius * math.asin(math.sqrt(a));
}

class LeaveReminders extends ChangeNotifier with WidgetsBindingObserver {
  LeaveReminders({
    required int studentId,
    required ReminderNotifications notifications,
    required LocationService location,
    required MeRepository me,
    required CatalogRepository catalog,
    required bool Function() locationOptIn,
    SharedPreferences? preferences,
    DateTime Function() clock = DateTime.now,
  }) : _key = 'leave_reminders.student.$studentId',
       _notifications = notifications,
       _location = location,
       _me = me,
       _catalog = catalog,
       _locationOptIn = locationOptIn,
       _preferences = preferences,
       _clock = clock;

  final String _key;
  final ReminderNotifications _notifications;
  final LocationService _location;
  final MeRepository _me;
  final CatalogRepository _catalog;
  final bool Function() _locationOptIn;
  final SharedPreferences? _preferences;
  final DateTime Function() _clock;

  final Map<int, ReminderEvent> _events = {};
  final Set<int> _busy = {};
  DateTime? _lastRefresh;
  bool _observing = false;
  bool _disposed = false;

  bool isOn(int eventId) => _events.containsKey(eventId);

  bool isBusy(int eventId) => _busy.contains(eventId);

  Future<void> start() async {
    final raw = _preferences?.getString(_key);
    if (raw != null) {
      try {
        for (final item in jsonDecode(raw) as List) {
          final event = ReminderEvent.fromJson(item as Map<String, dynamic>);
          if (event.startsAt.isAfter(_clock())) _events[event.id] = event;
        }
      } on FormatException {
      }
    }
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    notifyListeners();
    await refresh();
  }

  Future<LeavePlan> enable(CampusEvent event) async {
    final reminder = ReminderEvent.of(event);
    _busy.add(event.id);
    notifyListeners();
    try {
      await _notifications.requestPermission();
      final plan = await _plan(reminder);
      if (plan.notifyAt != null) {
        _events[event.id] = reminder;
        await _schedule(reminder, plan);
        await _save();
      }
      return plan;
    } finally {
      _busy.remove(event.id);
      notifyListeners();
    }
  }

  Future<void> disable(int eventId) async {
    _events.remove(eventId);
    notifyListeners();
    await _notifications.cancel(eventId);
    await _save();
  }

  Future<void> refresh() async {
    _lastRefresh = _clock();
    final now = _clock();
    for (final event in [..._events.values]) {
      if (!event.startsAt.isAfter(now)) {
        _events.remove(event.id);
        continue;
      }
      final plan = await _plan(event);
      if (plan.notifyAt == null) {
        await _notifications.cancel(event.id);
      } else {
        await _schedule(event, plan);
      }
    }
    await _save();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _events.isEmpty) return;
    final last = _lastRefresh;
    if (last == null || _clock().difference(last) > const Duration(minutes: 5)) {
      unawaited(refresh());
    }
  }

  Future<LeavePlan> _plan(ReminderEvent event) async {
    final now = _clock();
    final schedule = await _orEmpty(_me.schedule);
    final buildings = {for (final b in await _orEmpty(_catalog.buildings)) b.id: b};
    ({double latitude, double longitude})? here;
    if (_locationOptIn() && event.startsAt.difference(now) <= gpsHorizon) {
      final result = await _location.current();
      if (result case LocationResult(:final double latitude, :final double longitude)) {
        here = (latitude: latitude, longitude: longitude);
      }
    }
    return planLeave(
      event: event,
      schedule: schedule,
      buildings: buildings,
      now: now,
      here: here,
    );
  }

  Future<void> _schedule(ReminderEvent event, LeavePlan plan) {
    final message = leaveMessage(event, plan);
    return _notifications.schedule(
      eventId: event.id,
      at: plan.notifyAt!,
      title: message.title,
      body: message.body,
    );
  }

  Future<void> _save() async {
    await _preferences?.setString(
      _key,
      jsonEncode([for (final e in _events.values) e.toJson()]),
    );
  }

  static Future<List<T>> _orEmpty<T>(Future<List<T>> Function() load) async {
    try {
      return await load();
    } on ApiException {
      return const [];
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    for (final id in _events.keys) {
      unawaited(_notifications.cancel(id));
    }
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
