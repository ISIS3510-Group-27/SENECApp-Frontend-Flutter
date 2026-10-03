import 'package:flutter/material.dart';

import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';
import 'campus_event.dart';
import 'rso_category.dart';

/// Where a group stands with Uniandes Student Affairs. Student-created groups
/// start [pending]; only their creator sees them until they're [approved].
enum ReviewStatus { pending, approved, rejected }

/// A Registered Student Organization.
///
/// Lists (`GET /groups`) return the summary fields. The profile
/// (`GET /groups/{id}`) adds the rest, which stay empty on list items.
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
    required this.verified,
    this.imageUrl,
    this.isMember = false,
    this.isSaved = false,
    this.nextEventAt,
    this.foundedYear,
    this.contactEmail,
    this.instagramUrl,
    this.websiteUrl,
    this.meetingBuilding,
    this.upcomingEvents = const [],
    this.reviewStatus = ReviewStatus.approved,
    this.rejectionReason,
  });

  factory Rso.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>;
    final nextEvent = json['next_event'] as Map<String, dynamic>?;
    final building = json['meeting_building'] as Map<String, dynamic>?;
    final name = json['name'] as String;
    final color = parseHexColor(json['color'] as String?) ?? AppColors.primary;

    return Rso(
      id: json['id'] as int,
      name: name,
      category: RsoCategory.fromSlug(category['slug'] as String),
      members: json['member_count'] as int,
      description: json['description'] as String,
      tags: [
        for (final tag in json['tags'] as List)
          (tag as Map<String, dynamic>)['name'] as String,
      ],
      color: color,
      verified: json['verified'] as bool,
      imageUrl: json['image_url'] as String?,
      isMember: json['is_member'] as bool? ?? false,
      isSaved: json['is_saved'] as bool? ?? false,
      nextEventAt: nextEvent == null
          ? null
          : DateTime.parse(nextEvent['starts_at'] as String),
      foundedYear: json['founded_year'] as int?,
      contactEmail: json['contact_email'] as String?,
      instagramUrl: json['instagram_url'] as String?,
      websiteUrl: json['website_url'] as String?,
      meetingBuilding: building?['name'] as String?,
      reviewStatus:
          ReviewStatus.values.asNameMap()[json['review_status']] ??
          ReviewStatus.approved,
      rejectionReason: json['rejection_reason'] as String?,
      upcomingEvents: [
        for (final event in json['upcoming_events'] as List? ?? const [])
          CampusEvent.fromJson(
            event as Map<String, dynamic>,
            hostName: name,
            hostColor: color,
          ),
      ],
    );
  }

  final int id;
  final String name;
  final RsoCategory category;
  final int members;
  final String description;
  final List<String> tags;

  /// The organization's own accent, used for its icon tile, tags etc.
  final Color color;

  /// Officially recognised by Uniandes Student Affairs (as proposed).
  final bool verified;

  /// Cover photo hosted by the backend, if the group uploaded one.
  final String? imageUrl;

  /// Whether the student belonged to / had saved the group when it was
  /// fetched. `AppState` keeps the live answer after a join or save.
  final bool isMember;
  final bool isSaved;

  final DateTime? nextEventAt;

  final ReviewStatus reviewStatus;

  /// Why Student Affairs turned the proposal down, when it did.
  final String? rejectionReason;

  bool get isApproved => reviewStatus == ReviewStatus.approved;

  // --- Profile only ---------------------------------------------------------

  final int? foundedYear;
  final String? contactEmail;
  final String? instagramUrl;
  final String? websiteUrl;

  /// Where the group usually meets, e.g. `Edificio Mario Laserna`.
  final String? meetingBuilding;

  final List<CampusEvent> upcomingEvents;

  /// The bundled photo in `assets/images/orgs/`, without an extension, derived
  /// from the name: `Fotografía Uniandes` → `fotografia_uniandes`. Resolved by
  /// `OrgImage`, which prefers it over [imageUrl].
  String get imageSlug => _slugify(name);

  /// Next event e.g. `Sat, Aug 22 · 8:00 AM`.
  String? get nextEvent =>
      nextEventAt == null ? null : Dates.dayAndTime(nextEventAt!);

  /// Just the date half of [nextEvent], for the compact card on My RSOs.
  String? get nextEventDate =>
      nextEventAt == null ? null : Dates.day(nextEventAt!);

  static const _accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };

  static String _slugify(String name) {
    final plain = name.toLowerCase().split('').map((c) => _accents[c] ?? c);
    return plain
        .join()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}
