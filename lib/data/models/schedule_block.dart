import 'package:flutter/material.dart';

/// One weekly class in the student's schedule, in campus time.
///
/// The gaps between classes are the free time "Free right now" fills.
@immutable
class ScheduleBlock {
  const ScheduleBlock({
    required this.weekday,
    required this.start,
    required this.end,
    this.title,
    this.buildingId,
    this.buildingName,
  });

  factory ScheduleBlock.fromJson(Map<String, dynamic> json) {
    final building = json['building'] as Map<String, dynamic>?;
    return ScheduleBlock(
      weekday: json['weekday'] as int,
      start: _parseTime(json['start_time'] as String),
      end: _parseTime(json['end_time'] as String),
      title: json['title'] as String?,
      buildingId: building?['id'] as int?,
      buildingName: building?['name'] as String?,
    );
  }

  static const weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// 0 = Monday ... 6 = Sunday, as the backend counts.
  final int weekday;

  final TimeOfDay start;
  final TimeOfDay end;

  /// e.g. `Cálculo II`.
  final String? title;

  /// Where the class is: the backend uses it to guess where the student is
  /// between classes when GPS is off.
  final int? buildingId;
  final String? buildingName;

  /// For `PUT /me/schedule`.
  Map<String, Object?> toJson() => {
    'weekday': weekday,
    'start_time': _formatTime(start),
    'end_time': _formatTime(end),
    'title': (title?.trim().isEmpty ?? true) ? null : title!.trim(),
    'building_id': buildingId,
  };

  static int minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  /// Whether this class and [other] share any time on the same day.
  bool overlaps(ScheduleBlock other) =>
      weekday == other.weekday &&
      minutesOf(start) < minutesOf(other.end) &&
      minutesOf(other.start) < minutesOf(end);

  static TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:00';
}
