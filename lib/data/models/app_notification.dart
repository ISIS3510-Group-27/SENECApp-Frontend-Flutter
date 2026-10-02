import 'package:flutter/material.dart';

import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';

/// One entry in the notifications inbox (`GET /me/notifications`).
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.groupId,
    this.eventId,
    this.opened = false,
    this.dismissed = false,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as int,
        type: json['type'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        groupId: json['group_id'] as int?,
        eventId: json['event_id'] as int?,
        opened: json['opened_at'] != null,
        dismissed: json['dismissed_at'] != null,
      );

  final int id;

  /// `new_event`, `group_recommendation`, `group_message` or
  /// `event_reminder` (the families BQ8 compares), or `group_review`: the
  /// outcome of the student's group proposal.
  final String type;

  /// e.g. `New event from Tennis Uniandes`.
  final String title;

  /// e.g. `Drop-in · Tennis Uniandes`.
  final String body;

  final DateTime createdAt;

  /// The group a tap opens, if any.
  final int? groupId;
  final int? eventId;

  /// Tapped by the student. Counts as an interaction for BQ8.
  final bool opened;

  /// Cleared without being opened ("Mark all read").
  final bool dismissed;

  bool get unread => !opened && !dismissed;

  /// Relative age, e.g. `2h ago`.
  String get time => Dates.ago(createdAt);

  AppNotification copyWith({bool? opened, bool? dismissed}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    groupId: groupId,
    eventId: eventId,
    opened: opened ?? this.opened,
    dismissed: dismissed ?? this.dismissed,
  );

  Color get color => switch (type) {
    'new_event' || 'event_reminder' => AppColors.accent,
    'group_recommendation' => AppColors.teal,
    'group_message' => AppColors.blue,
    'group_review' => AppColors.violet,
    _ => AppColors.mutedForeground,
  };

  IconData get icon => switch (type) {
    'new_event' => Icons.event_rounded,
    'event_reminder' => Icons.alarm_rounded,
    'group_recommendation' => Icons.auto_awesome_rounded,
    'group_message' => Icons.forum_rounded,
    'group_review' => Icons.fact_check_rounded,
    _ => Icons.notifications_rounded,
  };
}
