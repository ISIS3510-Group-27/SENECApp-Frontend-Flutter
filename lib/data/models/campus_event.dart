import 'package:flutter/material.dart';

/// An event hosted by an organization.
@immutable
class CampusEvent {
  const CampusEvent({
    required this.id,
    required this.rsoId,
    required this.rsoName,
    required this.title,
    required this.date,
    required this.time,
    required this.location,
    required this.color,
  });

  final int id;

  /// The [Rso] that hosts this event; the link that makes a card tappable.
  final int rsoId;

  /// Denormalised host name. The prototype shows a shortened label here
  /// ("AI & ML Group") that does not always match the organization's full name.
  final String rsoName;

  final String title;
  final String date;
  final String time;
  final String location;
  final Color color;
}
