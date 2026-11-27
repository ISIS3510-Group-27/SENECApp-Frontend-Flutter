import 'package:flutter/foundation.dart';

import 'catalog.dart';

@immutable
class SuggestedSlot {
  const SuggestedSlot({
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.freeMembers,
    required this.freeRatio,
    required this.attendanceRate,
    required this.nextStartsAt,
  });

  factory SuggestedSlot.fromJson(Map<String, dynamic> json) => SuggestedSlot(
    weekday: json['weekday'] as int,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    freeMembers: json['free_members'] as int,
    freeRatio: (json['free_ratio'] as num).toDouble(),
    attendanceRate: (json['attendance_rate'] as num?)?.toDouble(),
    nextStartsAt: DateTime.parse(json['next_starts_at'] as String),
  );

  final int weekday;

  final String startTime;
  final String endTime;
  final int freeMembers;
  final double freeRatio;

  final double? attendanceRate;

  final DateTime nextStartsAt;

  SuggestedSlot upcoming(DateTime now) {
    var next = nextStartsAt;
    while (!next.isAfter(now)) {
      next = next.add(const Duration(days: 7));
    }
    if (next == nextStartsAt) return this;
    return SuggestedSlot(
      weekday: weekday,
      startTime: startTime,
      endTime: endTime,
      freeMembers: freeMembers,
      freeRatio: freeRatio,
      attendanceRate: attendanceRate,
      nextStartsAt: next,
    );
  }

  Duration get length {
    int minutes(String clock) {
      final parts = clock.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    return Duration(minutes: minutes(endTime) - minutes(startTime));
  }
}

@immutable
class BestTimes {
  const BestTimes({
    required this.members,
    required this.membersWithSchedule,
    required this.pastEvents,
    required this.slots,
  });

  factory BestTimes.fromJson(Map<String, dynamic> json) => BestTimes(
    members: json['members'] as int,
    membersWithSchedule: json['members_with_schedule'] as int,
    pastEvents: json['past_events'] as int,
    slots: [
      for (final slot in json['slots'] as List)
        SuggestedSlot.fromJson(slot as Map<String, dynamic>),
    ],
  );

  final int members;
  final int membersWithSchedule;
  final int pastEvents;
  final List<SuggestedSlot> slots;

  BestTimes upcoming(DateTime now) => BestTimes(
    members: members,
    membersWithSchedule: membersWithSchedule,
    pastEvents: pastEvents,
    slots: [for (final slot in slots) slot.upcoming(now)],
  );
}

@immutable
class AudienceCell {
  const AudienceCell({
    required this.hour,
    required this.building,
    required this.impressions,
    required this.interactions,
    required this.interactionRate,
  });

  factory AudienceCell.fromJson(Map<String, dynamic> json) {
    final building = json['building'] as Map<String, dynamic>?;
    return AudienceCell(
      hour: json['hour'] as int?,
      building: building == null ? null : Building.fromJson(building),
      impressions: json['impressions'] as int,
      interactions: json['interactions'] as int,
      interactionRate: (json['interaction_rate'] as num?)?.toDouble(),
    );
  }

  final int? hour;
  final Building? building;
  final int impressions;
  final int interactions;
  final double? interactionRate;
}

@immutable
class Audience {
  const Audience({
    required this.question,
    required this.answer,
    required this.bestTimeAndPlace,
    required this.byHour,
    required this.byBuilding,
  });

  factory Audience.fromJson(Map<String, dynamic> json) {
    List<AudienceCell> cells(String key) => [
      for (final cell in json[key] as List)
        AudienceCell.fromJson(cell as Map<String, dynamic>),
    ];
    return Audience(
      question: json['question'] as String,
      answer: json['answer'] as String,
      bestTimeAndPlace: cells('best_time_and_place'),
      byHour: cells('by_hour'),
      byBuilding: cells('by_building'),
    );
  }

  final String question;
  final String answer;
  final List<AudienceCell> bestTimeAndPlace;
  final List<AudienceCell> byHour;
  final List<AudienceCell> byBuilding;

  bool get isEmpty => bestTimeAndPlace.isEmpty && byBuilding.isEmpty;
}

@immutable
class ProfileField {
  const ProfileField({
    required this.field,
    required this.filled,
    required this.views,
    required this.correlation,
    required this.lift,
  });

  factory ProfileField.fromJson(Map<String, dynamic> json) => ProfileField(
    field: json['field'] as String,
    filled: json['filled'] as bool,
    views: json['views'] as int,
    correlation: (json['correlation'] as num?)?.toDouble(),
    lift: (json['lift'] as num?)?.toDouble(),
  );

  final String field;
  final bool filled;
  final int views;
  final double? correlation;
  final double? lift;
}

@immutable
class ProfileTips {
  const ProfileTips({
    required this.question,
    required this.answer,
    required this.filled,
    required this.total,
    required this.fields,
  });

  factory ProfileTips.fromJson(Map<String, dynamic> json) => ProfileTips(
    question: json['question'] as String,
    answer: json['answer'] as String,
    filled: json['filled'] as int,
    total: json['total'] as int,
    fields: [
      for (final field in json['fields'] as List)
        ProfileField.fromJson(field as Map<String, dynamic>),
    ],
  );

  final String question;
  final String answer;
  final int filled;
  final int total;
  final List<ProfileField> fields;

  List<ProfileField> get missing => [
    for (final field in fields)
      if (!field.filled) field,
  ];

  List<ProfileField> get present => [
    for (final field in fields)
      if (field.filled) field,
  ];
}
