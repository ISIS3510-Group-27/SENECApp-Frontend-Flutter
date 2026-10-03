import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/data/models/catalog.dart';
import 'package:senecapp/data/models/schedule_block.dart';
import 'package:senecapp/state/leave_reminders.dart';

void main() {
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

  ScheduleBlock wednesday(int from, int to, {int? buildingId}) =>
      ScheduleBlock(
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
}
