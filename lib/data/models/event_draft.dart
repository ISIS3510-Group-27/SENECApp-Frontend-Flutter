import 'package:flutter/foundation.dart';

enum DraftDelivery { editing, needsReview, published }

/// Unpublished form values, including incomplete or temporarily invalid input.
@immutable
class EventDraft {
  const EventDraft({
    this.title = '',
    this.room = '',
    this.capacity = '',
    this.description = '',
    this.date,
    this.startMinute,
    this.durationMinutes = 120,
    this.buildingId,
    this.delivery = DraftDelivery.editing,
    this.publishedEventId,
  });

  final String title;
  final String room;
  final String capacity;
  final String description;
  final DateTime? date;
  final int? startMinute;
  final int durationMinutes;
  final int? buildingId;
  final DraftDelivery delivery;
  final int? publishedEventId;

  static const lengths = [60, 90, 120, 180];

  DateTime? get startsAt => date == null || startMinute == null
      ? null
      : DateTime(
          date!.year,
          date!.month,
          date!.day,
          startMinute! ~/ 60,
          startMinute! % 60,
        );

  int? get capacityValue =>
      capacity.trim().isEmpty ? null : int.tryParse(capacity);

  bool canPublish(DateTime now) =>
      title.trim().length >= 3 &&
      title.length <= 200 &&
      room.length <= 200 &&
      description.length <= 2000 &&
      startsAt != null &&
      startsAt!.isAfter(now) &&
      lengths.contains(durationMinutes) &&
      (capacity.trim().isEmpty || (capacityValue ?? 0) > 0);

  bool get isEmpty =>
      title.isEmpty &&
      room.isEmpty &&
      capacity.isEmpty &&
      description.isEmpty &&
      date == null &&
      startMinute == null &&
      buildingId == null &&
      durationMinutes == 120;

  bool sameFields(EventDraft other) =>
      title == other.title &&
      room == other.room &&
      capacity == other.capacity &&
      description == other.description &&
      date == other.date &&
      startMinute == other.startMinute &&
      durationMinutes == other.durationMinutes &&
      buildingId == other.buildingId;

  EventDraft withDelivery(DraftDelivery value, {int? eventId}) => EventDraft(
    title: title,
    room: room,
    capacity: capacity,
    description: description,
    date: date,
    startMinute: startMinute,
    durationMinutes: durationMinutes,
    buildingId: buildingId,
    delivery: value,
    publishedEventId: eventId,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'title': title,
    'room': room,
    'capacity': capacity,
    'description': description,
    'date': date?.toIso8601String(),
    'start_minute': startMinute,
    'duration_minutes': durationMinutes,
    'building_id': buildingId,
    'delivery': delivery.name,
    'published_event_id': publishedEventId,
  };

  factory EventDraft.fromJson(Map<String, dynamic> json) {
    final minute = json['start_minute'] as int?;
    final length = json['duration_minutes'] as int;
    final delivery = DraftDelivery.values.asNameMap()[json['delivery']];
    if (json['version'] != 1 ||
        delivery == null ||
        (minute != null && (minute < 0 || minute >= 1440)) ||
        !lengths.contains(length)) {
      throw const FormatException('Unsupported event draft.');
    }
    return EventDraft(
      title: json['title'] as String,
      room: json['room'] as String,
      capacity: json['capacity'] as String,
      description: json['description'] as String,
      date: json['date'] == null
          ? null
          : DateTime.parse(json['date'] as String),
      startMinute: minute,
      durationMinutes: length,
      buildingId: json['building_id'] as int?,
      delivery: delivery,
      publishedEventId: json['published_event_id'] as int?,
    );
  }
}
