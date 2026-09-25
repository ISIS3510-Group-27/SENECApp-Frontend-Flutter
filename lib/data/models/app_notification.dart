import 'package:flutter/material.dart';

/// One entry in the notifications panel. (As the figma prototype)
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

  /// Who it came from - either an organization name, or "SENECApp"
  ///  for general system notifiicagions.
  final String source;

  final String message;

  /// Relative age of the notification, e.g. `2h ago`.
  final String time;

  final Color color;
}
