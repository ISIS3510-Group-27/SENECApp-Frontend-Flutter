import 'package:flutter/foundation.dart';

/// Something a student can be into (`AI/ML`, `Tennis`). Groups are tagged
/// with interests, and Explore can filter by them.
@immutable
class Interest {
  const Interest({required this.id, required this.name, this.categorySlug});

  factory Interest.fromJson(Map<String, dynamic> json) => Interest(
    id: json['id'] as int,
    name: json['name'] as String,
    categorySlug:
        (json['category'] as Map<String, dynamic>?)?['slug'] as String?,
  );

  final int id;
  final String name;

  /// The category it belongs to, e.g. `sports` for Tennis.
  final String? categorySlug;
}

/// A campus building where groups meet and events happen.
@immutable
class Building {
  const Building({
    required this.id,
    required this.code,
    required this.name,
    this.latitude,
    this.longitude,
  });

  factory Building.fromJson(Map<String, dynamic> json) => Building(
    id: json['id'] as int,
    code: json['code'] as String,
    name: json['name'] as String,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
  );

  /// What a class in the schedule points to.
  final int id;

  /// Short code the backend filters by, e.g. `ML`.
  final String code;

  /// e.g. `Edificio Mario Laserna`.
  final String name;

  final double? latitude;
  final double? longitude;
}
