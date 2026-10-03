/// How the student reached a group profile.
///
/// Sent when the profile is opened and again when they join, so the backend
/// can tell which path produces joins (BQ6) and which filters lead to opening
/// a group (BQ12). The names match the backend's values.
enum EntryPoint {
  /// Browsing Discover with no search or filter applied.
  explore,

  /// Discover with a search term or any filter applied.
  search,

  recommendation,
  notification,
  event,

  /// Anywhere else, e.g. the student's own groups.
  direct,
}

/// How the student reached an event's page. Sent when it is opened, so BQ3
/// can count which "Free right now" suggestions get looked at.
enum EventEntryPoint {
  /// A "Free right now" suggestion.
  freeNow('free_now'),

  /// The Events tab.
  events('events'),

  /// A group profile's upcoming events.
  groupDetail('group_detail'),

  /// A push or inbox notification.
  notification('notification'),

  reminder('reminder');

  const EventEntryPoint(this.value);

  /// What the backend receives.
  final String value;
}
