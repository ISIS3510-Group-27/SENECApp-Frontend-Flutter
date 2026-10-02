import 'package:flutter/foundation.dart';

import 'campus_event.dart';

/// Where the backend thinks the student is.
enum LocationSource {
  /// From the phone's GPS (only with the student's consent).
  gps,

  /// The building of their previous or next class.
  schedule,

  /// Unknown: no GPS and no class around this time.
  none,
}

/// An event that fits the student's free time.
@immutable
class EventSuggestion {
  const EventSuggestion({
    required this.event,
    required this.reasons,
    this.walkingMinutes,
  });

  factory EventSuggestion.fromJson(Map<String, dynamic> json) =>
      EventSuggestion(
        event: CampusEvent.fromJson(json['event'] as Map<String, dynamic>),
        reasons: [for (final reason in json['reasons'] as List) '$reason'],
        walkingMinutes: json['walking_minutes'] as int?,
      );

  final CampusEvent event;

  /// e.g. `4 min walk`, `Fits entirely in your free time`.
  final List<String> reasons;

  /// From where the student is; null when that's unknown.
  final int? walkingMinutes;
}

/// The answer to "what can I do right now?": the student's current or next
/// free block, where they are, and events that fit.
///
/// Every suggestion is logged as shown; [requestId] ties a later view of one
/// back to this answer (BQ3).
@immutable
class FreeNowSuggestions {
  const FreeNowSuggestions({
    required this.requestId,
    required this.scheduleKnown,
    required this.locationSource,
    required this.items,
    this.freeFrom,
    this.freeUntil,
    this.freeMinutes,
    this.buildingName,
    this.onCampus,
    this.message,
  });

  factory FreeNowSuggestions.fromJson(Map<String, dynamic> json) {
    final block = json['free_block'] as Map<String, dynamic>?;
    final location = json['location'] as Map<String, dynamic>;
    final building = location['building'] as Map<String, dynamic>?;
    return FreeNowSuggestions(
      requestId: json['request_id'] as String,
      scheduleKnown: json['schedule_known'] as bool,
      locationSource:
          LocationSource.values.asNameMap()[location['source']] ??
          LocationSource.none,
      items: [
        for (final item in json['items'] as List)
          EventSuggestion.fromJson(item as Map<String, dynamic>),
      ],
      freeFrom: block == null
          ? null
          : DateTime.parse(block['starts_at'] as String),
      freeUntil: block == null
          ? null
          : DateTime.parse(block['ends_at'] as String),
      freeMinutes: block?['minutes'] as int?,
      buildingName: building?['name'] as String?,
      onCampus: location['on_campus'] as bool?,
      message: json['message'] as String?,
    );
  }

  final String requestId;

  /// False when the student hasn't added classes; the backend then assumes
  /// the next two hours are free.
  final bool scheduleKnown;

  final LocationSource locationSource;
  final List<EventSuggestion> items;

  /// The free block, or all null when there is no more free time today.
  final DateTime? freeFrom;
  final DateTime? freeUntil;
  final int? freeMinutes;

  /// The building the student is at or nearest to.
  final String? buildingName;

  /// Only known from GPS.
  final bool? onCampus;

  /// The backend's explanation when there is nothing to suggest.
  final String? message;

  bool get hasFreeTime => freeUntil != null;
}
