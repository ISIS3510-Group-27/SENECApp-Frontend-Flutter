import 'package:flutter/material.dart';

/// The signed-in student, as `GET /me` returns them.
@immutable
class StudentProfile {
  const StudentProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.interests,
    this.program,
    this.semester,
    this.locationOptIn = false,
    this.notificationsOptIn = true,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) => StudentProfile(
    id: json['id'] as int,
    name: json['full_name'] as String,
    email: json['email'] as String,
    program: json['program'] as String?,
    semester: json['semester'] as int?,
    interests: [
      for (final interest in json['interests'] as List)
        (interest as Map<String, dynamic>)['name'] as String,
    ],
    locationOptIn: json['location_opt_in'] as bool? ?? false,
    notificationsOptIn: json['notifications_opt_in'] as bool? ?? true,
  );

  final int id;
  final String name;
  final String email;

  /// Degree, e.g. `Ingeniería de Sistemas`. Empty until the student fills it
  /// in.
  final String? program;

  final int? semester;

  final List<String> interests;

  /// Consent to use the phone's location for nearby suggestions.
  final bool locationOptIn;

  final bool notificationsOptIn;

  /// Initials for the avatar tile, e.g. `SA` (for sofia arango).
  String get initials => name
      .split(RegExp(r'[\s._-]+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}
