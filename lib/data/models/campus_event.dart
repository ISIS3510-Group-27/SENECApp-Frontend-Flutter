import 'package:flutter/material.dart';

import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';

/// An event hosted by an organization.
@immutable
class CampusEvent {
  const CampusEvent({
    required this.id,
    required this.rsoId,
    required this.rsoName,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.color,
    this.buildingName,
    this.buildingLatitude,
    this.buildingLongitude,
    this.locationDetail,
    this.isCancelled = false,
    this.checkedIn = false,
    this.description,
    this.capacity,
    this.attendeeCount,
  });

  /// Reads an event from the API.
  ///
  /// Event lists (`GET /events`) say which group hosts each event. The events
  /// nested in a group profile don't, so the profile passes its own
  /// [hostName] and [hostColor].
  factory CampusEvent.fromJson(
    Map<String, dynamic> json, {
    String? hostName,
    Color? hostColor,
  }) {
    final group = json['group'] as Map<String, dynamic>?;
    final building = json['building'] as Map<String, dynamic>?;
    return CampusEvent(
      id: json['id'] as int,
      rsoId: json['group_id'] as int,
      rsoName: group?['name'] as String? ?? hostName ?? '',
      title: json['title'] as String,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      color:
          parseHexColor(group?['color'] as String?) ??
          hostColor ??
          AppColors.accent,
      buildingName: building?['name'] as String?,
      buildingLatitude: (building?['latitude'] as num?)?.toDouble(),
      buildingLongitude: (building?['longitude'] as num?)?.toDouble(),
      locationDetail: json['location_detail'] as String?,
      isCancelled: json['is_cancelled'] as bool? ?? false,
      checkedIn: json['checked_in'] as bool? ?? false,
      description: json['description'] as String?,
      capacity: json['capacity'] as int?,
      attendeeCount: json['attendee_count'] as int?,
    );
  }

  final int id;

  /// The [Rso] that hosts this event, it's the link that makes a card tappable.
  final int rsoId;

  final String rsoName;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final Color color;

  /// e.g. `Edificio Mario Laserna`.
  final String? buildingName;

  final double? buildingLatitude;
  final double? buildingLongitude;

  /// Room or spot inside the building, e.g. `Salón 224`.
  final String? locationDetail;

  final bool isCancelled;

  /// The student scanned the QR code at this event.
  final bool checkedIn;

  final String? description;

  /// Maximum attendees, if the organizers set one.
  final int? capacity;

  /// Students checked in so far. Missing on events nested in a group profile.
  final int? attendeeCount;

  /// `Sat, Aug 22`
  String get date => Dates.day(startsAt);

  /// `8:00 AM`
  String get time => Dates.time(startsAt);

  /// When check-in opens before the event starts and closes after it ends.
  /// Mirrors the backend's defaults (`CHECK_IN_OPENS_MINUTES`,
  /// `CHECK_IN_CLOSES_MINUTES`); the backend has the final say.
  static const checkInOpensBefore = Duration(minutes: 30);
  static const checkInClosesAfter = Duration(minutes: 15);

  bool checkInOpenAt(DateTime now) =>
      !now.isBefore(startsAt.subtract(checkInOpensBefore)) &&
      !now.isAfter(endsAt.add(checkInClosesAfter));

  CampusEvent copyWith({bool? checkedIn}) => CampusEvent(
    id: id,
    rsoId: rsoId,
    rsoName: rsoName,
    title: title,
    startsAt: startsAt,
    endsAt: endsAt,
    color: color,
    buildingName: buildingName,
    buildingLatitude: buildingLatitude,
    buildingLongitude: buildingLongitude,
    locationDetail: locationDetail,
    isCancelled: isCancelled,
    checkedIn: checkedIn ?? this.checkedIn,
    description: description,
    capacity: capacity,
    attendeeCount: attendeeCount,
  );

  /// `8:00 AM - 10:00 AM`
  String get timeRange => '${Dates.time(startsAt)} - ${Dates.time(endsAt)}';

  /// `Edificio Mario Laserna · Salón 224`
  String get location {
    final parts = [?buildingName, ?locationDetail];
    return parts.isEmpty ? 'Location to be announced' : parts.join(' · ');
  }
}

/// `#3B82F6` → [Color]. Null for anything that isn't a 6-digit hex colour.
Color? parseHexColor(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}
