import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:senecapp/data/models/campus_event.dart';
import 'package:senecapp/data/models/catalog.dart';
import 'package:senecapp/data/models/schedule_block.dart';
import 'package:senecapp/data/reminders/reminder_notifications.dart';
import 'package:senecapp/state/leave_reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final eventStart = DateTime.utc(2026, 10, 7, 23);
  final event = ReminderEvent(
    id: 7,
    title: 'Doubles night',
    startsAt: eventStart,
    buildingName: 'Centro Deportivo',
    latitude: 4.6040,
    longitude: -74.0660,
  );
  const ml = Building(
    id: 1,
    code: 'ML',
    name: 'Edificio Mario Laserna',
    latitude: 4.6026,
    longitude: -74.0649,
  );
  final buildings = {ml.id: ml};

  ScheduleBlock wednesday(int from, int to, {int? buildingId}) => ScheduleBlock(
    weekday: 2,
    start: TimeOfDay(hour: from, minute: 0),
    end: TimeOfDay(hour: to, minute: 0),
    title: 'Cálculo II',
    buildingId: buildingId,
  );

  test('far away in time, the walk starts at the previous class', () {
    final plan = planLeave(
      event: event,
      schedule: [wednesday(14, 16, buildingId: 1)],
      buildings: buildings,
      now: DateTime.utc(2026, 10, 6, 12),
      here: (latitude: 4.70, longitude: -74.05),
    );

    expect(plan.origin, LeaveOrigin.previousClass);
    expect(plan.walkMinutes, 2);
    expect(plan.notifyAt, eventStart.subtract(const Duration(minutes: 7)));
  });

  test('close to the start, the walk is measured from here', () {
    final plan = planLeave(
      event: event,
      schedule: const [],
      buildings: buildings,
      now: eventStart.subtract(const Duration(hours: 1)),
      here: (latitude: 4.6116, longitude: -74.0660),
    );

    expect(plan.origin, LeaveOrigin.here);
    expect(plan.walkMinutes, 11);
    expect(plan.notifyAt, eventStart.subtract(const Duration(minutes: 16)));
  });

  test('a class at leave time pushes the reminder to its end', () {
    final plan = planLeave(
      event: event,
      schedule: [wednesday(16, 18, buildingId: 1)],
      buildings: buildings,
      now: DateTime.utc(2026, 10, 6, 12),
    );

    expect(plan.afterClass, isTrue);
    expect(plan.notifyAt, eventStart);
  });

  test('no reminder when the student is in class at the start', () {
    final plan = planLeave(
      event: event,
      schedule: [wednesday(17, 20)],
      buildings: buildings,
      now: DateTime.utc(2026, 10, 6, 12),
    );

    expect(plan.skip, LeaveSkip.inClass);
    expect(plan.blockingClass?.title, 'Cálculo II');
  });

  test('too late when the leave time already passed', () {
    final plan = planLeave(
      event: event,
      schedule: const [],
      buildings: buildings,
      now: eventStart.subtract(const Duration(minutes: 5)),
    );

    expect(plan.skip, LeaveSkip.tooLate);
    expect(plan.walkMinutes, 10);
  });

  test('the message names the walk and the start', () {
    final plan = planLeave(
      event: event,
      schedule: const [],
      buildings: buildings,
      now: DateTime.utc(2026, 10, 6, 12),
    );

    final message = leaveMessage(event, plan);

    expect(message.title, 'Time to leave for Doubles night');
    expect(message.body, startsWith('10 min walk to Centro Deportivo'));
  });

  group('Reminder activation', () {
    final campusEvent = CampusEvent(
      id: 7,
      rsoId: 1,
      rsoName: 'Club',
      title: 'Doubles night',
      startsAt: DateTime.utc(2030, 1, 6, 23),
      endsAt: DateTime.utc(2030, 1, 7, 1),
      color: Colors.amber,
    );

    for (final allowed in [false, true]) {
      test(
        'permission $allowed determines activation and persistence',
        () async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final notifications = _TestNotifications(allowed: allowed);
          final services = testServices();
          final reminders = LeaveReminders(
            studentId: 1,
            notifications: notifications,
            location: FakeLocationService(),
            me: services.me,
            catalog: services.catalog,
            locationOptIn: () => false,
            preferences: prefs,
            clock: () => DateTime.utc(2030, 1, 6, 12),
          );
          addTearDown(reminders.dispose);

          final plan = await reminders.enable(campusEvent);

          expect(reminders.isOn(7), allowed);
          expect(reminders.isBusy(7), isFalse);
          expect(notifications.scheduled, allowed ? [7] : isEmpty);
          expect(prefs.containsKey('leave_reminders.student.1'), allowed);
          expect(
            plan.skip,
            allowed ? isNull : LeaveSkip.notificationsUnavailable,
          );
        },
      );
    }

    test(
      'failed scheduling leaves reminder off and clears busy state',
      () async {
        final services = testServices();
        final reminders = LeaveReminders(
          studentId: 1,
          notifications: _TestNotifications(allowed: true, fail: true),
          location: FakeLocationService(),
          me: services.me,
          catalog: services.catalog,
          locationOptIn: () => false,
          clock: () => DateTime.utc(2030, 1, 6, 12),
        );
        addTearDown(reminders.dispose);

        await expectLater(
          reminders.enable(campusEvent),
          throwsA(isA<PlatformException>()),
        );

        expect(reminders.isOn(7), isFalse);
        expect(reminders.isBusy(7), isFalse);
      },
    );
  });
}

class _TestNotifications extends DisabledReminderNotifications {
  _TestNotifications({required this.allowed, this.fail = false});

  final bool allowed;
  final bool fail;
  final List<int> scheduled = [];

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  Future<void> schedule({
    required int eventId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    if (fail) throw PlatformException(code: 'schedule-failed');
    scheduled.add(eventId);
  }
}
