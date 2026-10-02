import 'package:flutter/foundation.dart';

/// Something a student can be into (`AI/ML`, `Tennis`). Groups are tagged
/// with interests, and Explore can filter by them.
@immutable
class Interest {
  const Interest({required this.id, required this.name});

  factory Interest.fromJson(Map<String, dynamic> json) =>
      Interest(id: json['id'] as int, name: json['name'] as String);

  final int id;
  final String name;
}

/// A campus building where groups meet and events happen.
@immutable
class Building {
  const Building({required this.code, required this.name});

  factory Building.fromJson(Map<String, dynamic> json) =>
      Building(code: json['code'] as String, name: json['name'] as String);

  /// Short code the backend filters by, e.g. `ML`.
  final String code;

  /// e.g. `Edificio Mario Laserna`.
  final String name;
}
