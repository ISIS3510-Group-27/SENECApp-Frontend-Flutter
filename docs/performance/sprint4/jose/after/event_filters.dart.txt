import '../../data/models/campus_event.dart';

enum EventDateFilter {
  any('Any date'),
  today('Today'),
  nextSevenDays('Next 7 days');

  const EventDateFilter(this.label);

  final String label;
}

List<CampusEvent> filterEvents({
  required List<CampusEvent> events,
  required String query,
  required EventDateFilter dateFilter,
  required DateTime now,
}) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(_spaces)
      .where((term) => term.isNotEmpty)
      .toList();

  if (terms.isEmpty && dateFilter == EventDateFilter.any) {
    return List.of(events);
  }

  // Date bounds belong to this filtering call, not to each event in the list.
  final start = dateFilter == EventDateFilter.any
      ? null
      : DateTime(now.year, now.month, now.day);
  final end = start?.add(
    Duration(days: dateFilter == EventDateFilter.today ? 1 : 7),
  );

  final filtered = events.where((event) {
    if (start != null &&
        (event.isCancelled ||
            event.startsAt.isBefore(start) ||
            !event.startsAt.isBefore(end!))) {
      return false;
    }
    if (terms.isEmpty) return true;

    return terms.every(_searchText(event).contains);
  }).toList();

  filtered.sort((a, b) {
    final time = a.startsAt.compareTo(b.startsAt);
    return time == 0 ? a.id.compareTo(b.id) : time;
  });
  return filtered;
}

final _spaces = RegExp(r'\s+');

/// Micro-optimization (Sprint 4): the lower-cased text an event is searched
/// by, built once per event object instead of on every keystroke. An
/// [Expando] attaches it to the event without changing the model, and lets it
/// go with the event when a new list replaces it.
final _searchTexts = Expando<String>('event search text');

String _searchText(CampusEvent event) => _searchTexts[event] ??= [
  event.title,
  event.rsoName,
  event.location,
].join(' ').toLowerCase();

bool eventIsInNextSevenDays(CampusEvent event, DateTime now) =>
    _matchesDate(event, EventDateFilter.nextSevenDays, now);

bool _matchesDate(CampusEvent event, EventDateFilter filter, DateTime now) {
  final start = DateTime(now.year, now.month, now.day);
  return switch (filter) {
    EventDateFilter.any => true,
    EventDateFilter.today =>
      !event.startsAt.isBefore(start) &&
          event.startsAt.isBefore(start.add(const Duration(days: 1))),
    EventDateFilter.nextSevenDays =>
      !event.startsAt.isBefore(start) &&
          event.startsAt.isBefore(start.add(const Duration(days: 7))),
  };
}
