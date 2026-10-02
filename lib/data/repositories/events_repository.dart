import '../api/api_client.dart';
import '../models/campus_event.dart';

/// Events on the backend.
class EventsRepository {
  const EventsRepository(this._api);

  final ApiClient _api;

  /// Events that haven't ended yet, soonest first. [mine] keeps only those of
  /// the student's groups. [startsAfter] reaches back into the past.
  Future<List<CampusEvent>> list({
    bool mine = false,
    DateTime? startsAfter,
    int limit = 50,
    int offset = 0,
  }) async {
    final json =
        await _api.get(
              '/events',
              query: {
                if (mine) 'mine': true,
                'starts_after': startsAfter?.toUtc().toIso8601String(),
                'limit': limit,
                if (offset > 0) 'offset': offset,
              },
            )
            as Map<String, dynamic>;
    return [
      for (final item in json['items'] as List)
        CampusEvent.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// How many events of the student's groups since [since] they checked in
  /// to. Walks every page, since a semester holds more than one.
  Future<int> attendedSince(DateTime since) async {
    const pageSize = 100;
    var attended = 0;
    for (var offset = 0; ; offset += pageSize) {
      final page = await list(
        mine: true,
        startsAfter: since,
        limit: pageSize,
        offset: offset,
      );
      attended += page.where((e) => e.checkedIn).length;
      if (page.length < pageSize) return attended;
    }
  }
}
