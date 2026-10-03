import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/data/models/campus_event.dart';
import 'package:senecapp/data/models/schedule_block.dart';
import 'package:senecapp/features/events/event_planning.dart';

void main() {
  const color = Colors.amber;

  CampusEvent event({
    required int id,
    required DateTime startsAt,
    required DateTime endsAt,
    bool cancelled = false,
    String title = 'Campus Talk',
  }) => CampusEvent(
    id: id,
    rsoId: 1,
    rsoName: 'AI Club',
    title: title,
    startsAt: startsAt,
    endsAt: endsAt,
    color: color,
    buildingName: 'ML',
    locationDetail: 'Auditorium',
    isCancelled: cancelled,
    description: 'Bring your laptop.',
  );

  test('conflictingClasses uses Bogotá weekdays and exclusive end bounds', () {
    final schedule = [
      const ScheduleBlock(
        weekday: 4,
        start: TimeOfDay(hour: 9, minute: 0),
        end: TimeOfDay(hour: 10, minute: 0),
        title: 'Mobile Apps',
        buildingName: 'ML',
      ),
      const ScheduleBlock(
        weekday: 4,
        start: TimeOfDay(hour: 10, minute: 30),
        end: TimeOfDay(hour: 11, minute: 30),
        title: 'Databases',
      ),
    ];

    final conflicts = conflictingClasses(
      event(
        id: 1,
        startsAt: DateTime.utc(2026, 10, 2, 15, 15),
        endsAt: DateTime.utc(2026, 10, 2, 15, 45),
      ),
      schedule,
    );

    expect(conflicts.map((block) => block.title), ['Databases']);
  });

  test('itinerary maximizes complete non-overlapping future events', () {
    final now = DateTime(2026, 10, 2, 8);
    final events = [
      event(
        id: 1,
        startsAt: DateTime(2026, 10, 2, 9),
        endsAt: DateTime(2026, 10, 2, 12),
      ),
      event(
        id: 2,
        startsAt: DateTime(2026, 10, 2, 9),
        endsAt: DateTime(2026, 10, 2, 10),
      ),
      event(
        id: 3,
        startsAt: DateTime(2026, 10, 2, 10),
        endsAt: DateTime(2026, 10, 2, 11),
      ),
      event(
        id: 4,
        startsAt: DateTime(2026, 10, 2, 11),
        endsAt: DateTime(2026, 10, 2, 12),
        cancelled: true,
      ),
      event(
        id: 5,
        startsAt: DateTime(2026, 10, 2, 7),
        endsAt: DateTime(2026, 10, 2, 8, 30),
      ),
    ];

    final itinerary = buildEventItinerary(events, now: now);

    expect(itinerary.map((event) => event.id), [2, 3]);
  });

  test('eventSummary includes shareable event details', () {
    final summary = eventSummary(
      event(
        id: 1,
        title: 'Flutter Night',
        startsAt: DateTime(2026, 10, 2, 18),
        endsAt: DateTime(2026, 10, 2, 20),
      ),
    );

    expect(summary, contains('Flutter Night'));
    expect(summary, contains('Hosted by AI Club'));
    expect(summary, contains('ML · Auditorium'));
    expect(summary, contains('Bring your laptop.'));
  });
}
