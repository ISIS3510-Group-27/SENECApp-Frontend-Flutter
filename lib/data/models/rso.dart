import 'package:flutter/material.dart';

import 'rso_category.dart';

/// A Registered Student Organization.
@immutable
class Rso {
  const Rso({
    required this.id,
    required this.name,
    required this.category,
    required this.members,
    required this.description,
    required this.tags,
    required this.color,
    required this.imageSlug,
    required this.verified,
    this.nextEvent,
  });

  final int id;
  final String name;
  final RsoCategory category;
  final int members;
  final String description;
  final List<String> tags;

  /// The organization's own accent, used for its icon tile, tags etc.
  final Color color;

  /// The orgs photo in `assets/images/orgs/`, without
  /// an extension. Resolved by `OrgImage`, it falls back to a gradient when
  /// the file has not been added yet.
  final String imageSlug;

  /// Officially recognised by Uniandes Student Affairs (as proposed).
  final bool verified;

  /// Next event e.g. `Sat, Aug 22 - 8:00 AM`.
  final String? nextEvent;

  /// Just the date half of [nextEvent], for the compact card on My RSOs.
  String? get nextEventDate => nextEvent?.split('·').first.trim();
}
