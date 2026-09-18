import 'package:flutter/material.dart';

/// One entry in the notifications panel.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.source,
    required this.message,
    required this.time,
    required this.color,
  });

  final int id;

  /// Who it came from - an organization name, or "SENECApp" for system notices.
  final String source;

  final String message;

  /// Relative age, e.g. `2h ago`.
  final String time;

  final Color color;
}
