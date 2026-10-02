import 'package:flutter/foundation.dart';

import 'rso_category.dart';

/// Order of the Explore results. Names match the backend's `sort` values.
enum GroupSort {
  popular('Most popular'),
  newest('Newest'),
  name('A-Z'),
  upcoming('Next event');

  const GroupSort(this.label);

  final String label;
}

/// What the student searched for on Discover: the text, the category chip and
/// everything in the Filters sheet.
@immutable
class GroupFilters {
  const GroupFilters({
    this.query = '',
    this.category = RsoCategory.all,
    this.interestIds = const {},
    this.buildingCodes = const {},
    this.verifiedOnly = false,
    this.withUpcomingEvents = false,
    this.sort = GroupSort.popular,
  });

  final String query;
  final RsoCategory category;
  final Set<int> interestIds;
  final Set<String> buildingCodes;
  final bool verifiedOnly;
  final bool withUpcomingEvents;
  final GroupSort sort;

  /// Anything that narrows the results. A group opened from narrowed results
  /// was found by searching, not by browsing (BQ6, BQ12).
  bool get isSearch =>
      query.trim().isNotEmpty || category != RsoCategory.all || sheetCount > 0;

  /// How many filters are set in the sheet, for the badge on its button. Sort
  /// only reorders, so it doesn't count.
  int get sheetCount =>
      interestIds.length +
      buildingCodes.length +
      (verifiedOnly ? 1 : 0) +
      (withUpcomingEvents ? 1 : 0);

  /// The `GET /groups` query. Unset filters are left out: the backend logs
  /// every filter it receives (BQ12), so sending `verified=false` would count
  /// as using the filter.
  Map<String, Object?> toQuery() => {
    if (query.trim().isNotEmpty) 'q': query.trim(),
    if (category != RsoCategory.all) 'category': category.slug,
    if (interestIds.isNotEmpty) 'interest_id': interestIds.toList()..sort(),
    if (buildingCodes.isNotEmpty) 'building': buildingCodes.toList()..sort(),
    if (verifiedOnly) 'verified': true,
    if (withUpcomingEvents) 'has_upcoming_events': true,
    if (sort != GroupSort.popular) 'sort': sort.name,
  };

  GroupFilters copyWith({
    String? query,
    RsoCategory? category,
    Set<int>? interestIds,
    Set<String>? buildingCodes,
    bool? verifiedOnly,
    bool? withUpcomingEvents,
    GroupSort? sort,
  }) => GroupFilters(
    query: query ?? this.query,
    category: category ?? this.category,
    interestIds: interestIds ?? this.interestIds,
    buildingCodes: buildingCodes ?? this.buildingCodes,
    verifiedOnly: verifiedOnly ?? this.verifiedOnly,
    withUpcomingEvents: withUpcomingEvents ?? this.withUpcomingEvents,
    sort: sort ?? this.sort,
  );

  /// The sheet's filters back to their defaults; text and category stay.
  GroupFilters clearSheet() => GroupFilters(query: query, category: category);
}
