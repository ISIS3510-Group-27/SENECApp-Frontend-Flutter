import 'package:flutter/material.dart';

/// The nine discovery categories.
///
/// [all] is a filter-only member: it never belongs to an organization, it only
/// appears as the leading chip on Discover. Anything that lists categories for
/// *assignment* (the create form) uses [assignable].
enum RsoCategory {
  all('All', Icons.bolt_rounded),
  sports('Sports', Icons.fitness_center_rounded),
  business('Business', Icons.trending_up_rounded),
  technology('Technology', Icons.menu_book_rounded),
  arts('Arts', Icons.music_note_rounded),
  travel('Travel', Icons.flight_rounded),
  cars('Cars', Icons.directions_car_rounded),
  social('Social', Icons.local_cafe_rounded),
  international('International', Icons.public_rounded);

  const RsoCategory(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Categories an organization can actually be filed under.
  static List<RsoCategory> get assignable =>
      values.where((c) => c != RsoCategory.all).toList();
}
