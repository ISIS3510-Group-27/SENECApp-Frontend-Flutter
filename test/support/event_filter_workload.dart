import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:senecapp/data/models/campus_event.dart';
import 'package:senecapp/features/events/event_filters.dart';

/// Fixed synthetic input; never sent to the backend or used by the release app.
List<CampusEvent> eventFilterFixture(int count) {
  final day = DateTime(2026, 11, 27);
  return [
    for (var id = 1; id <= count; id++)
      CampusEvent(
        id: id,
        rsoId: id % 4 + 1,
        rsoName: id.isEven ? 'AI Club' : 'Travel Club',
        title: id % 4 == 0 ? 'Robotics meetup $id' : 'Community session $id',
        startsAt: day.add(Duration(days: id % 10 - 1, hours: 9 + id % 8)),
        endsAt: day.add(Duration(days: id % 10 - 1, hours: 10 + id % 8)),
        color: Colors.amber,
        buildingName: id.isEven ? 'ML' : 'SD',
        isCancelled: id % 17 == 0,
      ),
  ];
}

/// CPU workload for identical BEFORE/AFTER profiling sessions. Times are for
/// repeated filtering, not screen-load time or a frame-rendering benchmark.
Map<String, Object> runEventFilterWorkload({
  int iterations = 5000,
  int rounds = 3,
}) {
  final now = DateTime(2026, 11, 27, 10);
  final measurements = <Map<String, Object>>[];
  final outputs = <String, List<int>>{};
  var checksum = 0;
  for (final count in [50, 160]) {
    final events = eventFilterFixture(count);
    for (final (name, query, date) in [
      ('all', '', EventDateFilter.any),
      ('today', '', EventDateFilter.today),
      ('week', '', EventDateFilter.nextSevenDays),
      ('search', 'ai ml', EventDateFilter.any),
      ('search_week', 'robotics', EventDateFilter.nextSevenDays),
    ]) {
      List<CampusEvent> filter() => filterEvents(
        events: events,
        query: query,
        dateFilter: date,
        now: now,
      );
      outputs['$count:$name'] = filter().map((event) => event.id).toList();
      for (var warmup = 0; warmup < 200; warmup++) {
        filter();
      }
      for (var round = 0; round < rounds; round++) {
        Timeline.startSync(
          'event_filters.$count.$name',
          arguments: {
            'events': count,
            'iterations': iterations,
            'round': round,
          },
        );
        final timer = Stopwatch()..start();
        for (var i = 0; i < iterations; i++) {
          final selected = filter();
          checksum =
              (checksum +
                  selected.length +
                  (selected.isEmpty ? 0 : selected.first.id)) &
              0x7fffffff;
        }
        timer.stop();
        Timeline.finishSync();
        measurements.add({
          'events': count,
          'scenario': name,
          'round': round,
          'iterations': iterations,
          'elapsed_us': timer.elapsedMicroseconds,
        });
      }
    }
  }
  return {
    'schema_version': 1,
    'fixture_date': now.toIso8601String(),
    'measurements': measurements,
    'output_ids': outputs,
    'checksum': checksum,
  };
}
