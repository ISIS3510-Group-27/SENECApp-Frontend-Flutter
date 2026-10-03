import 'package:flutter/material.dart';

import '../../core/format/dates.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/schedule_block.dart';

const _bogota = Duration(hours: -5);

List<ScheduleBlock> conflictingClasses(
  CampusEvent event,
  List<ScheduleBlock> schedule,
) {
  if (!event.endsAt.isAfter(event.startsAt)) return const [];

  final start = _inBogota(event.startsAt);
  final end = _inBogota(event.endsAt);
  final conflicts = <ScheduleBlock>[];

  for (
    var day = DateTime(start.year, start.month, start.day);
    day.isBefore(end) || DateUtils.isSameDay(day, end);
    day = day.add(const Duration(days: 1))
  ) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final eventStart = start.isAfter(dayStart) ? start : dayStart;
    final eventEnd = end.isBefore(dayEnd) ? end : dayEnd;
    if (!eventEnd.isAfter(eventStart)) continue;

    final weekday = day.weekday - 1;
    for (final block in schedule.where((b) => b.weekday == weekday)) {
      final classStart = dayStart.add(_timeOffset(block.start));
      final classEnd = dayStart.add(_timeOffset(block.end));
      if (eventStart.isBefore(classEnd) && classStart.isBefore(eventEnd)) {
        conflicts.add(block);
      }
    }
  }

  return conflicts;
}

String eventSummary(CampusEvent event) {
  final lines = [
    event.title,
    'Hosted by ${event.rsoName}',
    '${event.date}, ${event.timeRange}',
    event.location,
    if (event.isCancelled) 'Status: Cancelled',
    ?event.description,
  ];
  return lines.join('\n');
}

List<CampusEvent> buildEventItinerary(
  List<CampusEvent> events, {
  required DateTime now,
}) {
  final candidates =
      events
          .where(
            (event) =>
                !event.isCancelled &&
                event.startsAt.isAfter(now) &&
                event.endsAt.isAfter(event.startsAt),
          )
          .toList()
        ..sort((a, b) {
          final end = a.endsAt.compareTo(b.endsAt);
          if (end != 0) return end;
          final start = a.startsAt.compareTo(b.startsAt);
          return start == 0 ? a.id.compareTo(b.id) : start;
        });

  final selected = <CampusEvent>[];
  DateTime? lastEnd;
  for (final event in candidates) {
    if (lastEnd == null || !event.startsAt.isBefore(lastEnd)) {
      selected.add(event);
      lastEnd = event.endsAt;
    }
  }
  return selected;
}

String scheduleBlockLabel(ScheduleBlock block) {
  final title = block.title?.trim();
  final name = title == null || title.isEmpty ? 'Class' : title;
  final location = block.buildingName;
  final start = _formatTime(block.start);
  final end = _formatTime(block.end);
  return [
    name,
    '$start - $end',
    if (location != null && location.trim().isNotEmpty) location,
  ].join(' · ');
}

DateTime _inBogota(DateTime value) {
  final wallTime = value.toUtc().add(_bogota);
  return DateTime(
    wallTime.year,
    wallTime.month,
    wallTime.day,
    wallTime.hour,
    wallTime.minute,
    wallTime.second,
    wallTime.millisecond,
    wallTime.microsecond,
  );
}

Duration _timeOffset(TimeOfDay time) =>
    Duration(hours: time.hour, minutes: time.minute);

String _formatTime(TimeOfDay time) {
  final fake = DateTime(2026, 1, 1, time.hour, time.minute);
  return Dates.time(fake);
}
