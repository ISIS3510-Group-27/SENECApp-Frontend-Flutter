import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/data/models/campus_event.dart';
import 'package:senecapp/features/events/event_filters.dart';

void main() {
  const color = Colors.amber;

  CampusEvent event({
    required int id,
    required String title,
    required String rso,
    required DateTime startsAt,
    String? building,
    bool cancelled = false,
  }) => CampusEvent(
    id: id,
    rsoId: 10 + id,
    rsoName: rso,
    title: title,
    startsAt: startsAt,
    endsAt: startsAt.add(const Duration(hours: 1)),
    color: color,
    buildingName: building,
    isCancelled: cancelled,
  );

  test('search matches title, organization and place with all query terms', () {
    final events = [
      event(
        id: 2,
        title: 'Robotics Jam',
        rso: 'AI Club',
        startsAt: DateTime(2026, 10, 5, 10),
        building: 'ML',
      ),
      event(
        id: 1,
        title: 'Photo Walk',
        rso: 'Photography',
        startsAt: DateTime(2026, 10, 4, 10),
        building: 'SD',
      ),
    ];

    final result = filterEvents(
      events: events,
      query: 'ai ml',
      dateFilter: EventDateFilter.any,
      now: DateTime(2026, 10, 2),
    );

    expect(result.map((event) => event.id), [2]);
  });

  test('today and next seven days use local day bounds and skip cancelled', () {
    final now = DateTime(2026, 10, 2, 11);
    final events = [
      event(
        id: 1,
        title: 'Yesterday',
        rso: 'A',
        startsAt: DateTime(2026, 10, 1, 23),
      ),
      event(
        id: 2,
        title: 'Today',
        rso: 'A',
        startsAt: DateTime(2026, 10, 2, 22),
      ),
      event(
        id: 3,
        title: 'Cancelled',
        rso: 'A',
        startsAt: DateTime(2026, 10, 3, 10),
        cancelled: true,
      ),
      event(
        id: 4,
        title: 'Six days',
        rso: 'A',
        startsAt: DateTime(2026, 10, 8, 23),
      ),
      event(
        id: 5,
        title: 'Seven days',
        rso: 'A',
        startsAt: DateTime(2026, 10, 9),
      ),
    ];

    expect(
      filterEvents(
        events: events,
        query: '',
        dateFilter: EventDateFilter.today,
        now: now,
      ).map((event) => event.id),
      [2],
    );

    expect(
      filterEvents(
        events: events,
        query: '',
        dateFilter: EventDateFilter.nextSevenDays,
        now: now,
      ).map((event) => event.id),
      [2, 4],
    );
  });

  test('results are ordered by start time then id', () {
    final startsAt = DateTime(2026, 10, 2, 10);
    final events = [
      event(id: 3, title: 'C', rso: 'A', startsAt: startsAt),
      event(id: 1, title: 'A', rso: 'A', startsAt: startsAt),
      event(
        id: 2,
        title: 'B',
        rso: 'A',
        startsAt: startsAt.subtract(const Duration(hours: 1)),
      ),
    ];

    final result = filterEvents(
      events: events,
      query: 'a',
      dateFilter: EventDateFilter.any,
      now: DateTime(2026, 10, 2),
    );

    expect(result.map((event) => event.id), [2, 1, 3]);
  });
}
