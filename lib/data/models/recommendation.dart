import 'package:flutter/foundation.dart';

import 'rso.dart';

/// A group the recommender picked for the student, and why.
@immutable
class GroupRecommendation {
  const GroupRecommendation({required this.group, required this.reasons});

  factory GroupRecommendation.fromJson(Map<String, dynamic> json) =>
      GroupRecommendation(
        group: Rso.fromJson(json['group'] as Map<String, dynamic>),
        reasons: [for (final reason in json['reasons'] as List) '$reason'],
      );

  final Rso group;

  /// Ready to show, strongest first, e.g. `Matches your interests: Tennis`.
  final List<String> reasons;
}

/// One answer from the group recommender.
///
/// The backend logs every group in it as shown to the student. [requestId]
/// ties a later view or join back to this list, which is how BQ2 measures
/// which recommendations work.
@immutable
class GroupRecommendations {
  const GroupRecommendations({
    required this.requestId,
    required this.modelVersion,
    required this.items,
  });

  factory GroupRecommendations.fromJson(Map<String, dynamic> json) =>
      GroupRecommendations(
        requestId: json['request_id'] as String,
        modelVersion: json['model_version'] as String,
        items: [
          for (final item in json['items'] as List)
            GroupRecommendation.fromJson(item as Map<String, dynamic>),
        ],
      );

  final String requestId;

  /// The recommender's weights version; it retrains nightly.
  final String modelVersion;

  final List<GroupRecommendation> items;
}
