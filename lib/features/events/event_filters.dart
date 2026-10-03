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
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();

  final filtered = events.where((event) {
    if (event.isCancelled && dateFilter != EventDateFilter.any) return false;
    if (!_matchesDate(event, dateFilter, now)) return false;
    if (terms.isEmpty) return true;

    final haystack = [
      event.title,
      event.rsoName,
      event.location,
    ].join(' ').toLowerCase();
    return terms.every(haystack.contains);
  }).toList();

  if (terms.isNotEmpty || dateFilter != EventDateFilter.any) {
    filtered.sort((a, b) {
      final time = a.startsAt.compareTo(b.startsAt);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
  }
  return filtered;
}

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
