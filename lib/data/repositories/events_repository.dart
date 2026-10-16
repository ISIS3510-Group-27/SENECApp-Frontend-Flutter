import '../../core/cache/lru_cache.dart';
import '../api/api_client.dart';
import '../local/offline_cache.dart';
import '../models/campus_event.dart';
import '../models/check_in.dart';
import '../models/entry_point.dart';

/// Events on the backend.
///
/// The two lists the Events tab shows (all upcoming, and my groups'), every
/// event page opened, an organizer's check-in QR codes and the semester's
/// attendance count are kept on the phone for when the backend can't be
/// reached. Event pages opened in this session are also kept in memory
/// ([recentDetail]).
class EventsRepository {
  EventsRepository(this._api, {OfflineCache? cache})
    : _cache = cache ?? OfflineCache.disabled();

  final ApiClient _api;
  final OfflineCache _cache;

  /// Like group profiles: going back to an event page is common, and 30 pages
  /// of a few KB each cost little memory.
  final _details = LruCache<int, CampusEvent>(capacity: 30);

  static String listKey({required bool mine}) =>
      mine ? 'events:mine' : 'events:all';
  static String detailKey(int id) => 'event:$id';
  static const attendedKey = 'attended';

  /// Events that haven't ended yet, soonest first. [mine] keeps only those of
  /// the student's groups. [startsAfter] reaches back into the past.
  ///
  /// The default lists (no [startsAfter], first page) are kept for offline
  /// use; other pages are only used to count attendance.
  Future<List<CampusEvent>> list({
    bool mine = false,
    DateTime? startsAfter,
    int limit = 50,
    int offset = 0,
  }) {
    Future<Object?> fetch() => _api.get(
      '/events',
      query: {
        if (mine) 'mine': true,
        'starts_after': startsAfter?.toUtc().toIso8601String(),
        'limit': limit,
        if (offset > 0) 'offset': offset,
      },
    );
    if (startsAfter != null || offset > 0) {
      return fetch().then((json) => _events((json! as Map)['items']));
    }
    final name = mine ? 'mine' : 'all';
    return _cache.networkFirst(
      listKey(mine: mine),
      fetch: () async => (await fetch() as Map<String, dynamic>)['items'],
      parse: _events,
      save: (json) => _cache.store.saveEvents(name, json! as List),
      load: () => _cache.store.events(name),
    );
  }

  Future<CampusEvent> create(
    int groupId, {
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? description,
    int? buildingId,
    String? locationDetail,
    int? capacity,
  }) async => CampusEvent.fromJson(
    await _api.post(
          '/groups/$groupId/events',
          body: {
            'title': title,
            'starts_at': startsAt.toUtc().toIso8601String(),
            'ends_at': endsAt.toUtc().toIso8601String(),
            'description': ?description,
            'building_id': ?buildingId,
            'location_detail': ?locationDetail,
            'capacity': ?capacity,
          },
        )
        as Map<String, dynamic>,
  );

  /// One event's page. Each call is logged as a view (BQ3), so call it once
  /// per visit, with how the student got there.
  Future<CampusEvent> detail(
    int id, {
    required EventEntryPoint entryPoint,
    String? recRequestId,
  }) async {
    final event = await _cache.networkFirst(
      detailKey(id),
      fetch: () => _api.get(
        '/events/$id',
        query: {
          'entry_point': entryPoint.value,
          'rec_request_id': recRequestId,
        },
      ),
      parse: (json) => CampusEvent.fromJson(json! as Map<String, dynamic>),
      save: (json) =>
          _cache.store.saveEventDetail(json! as Map<String, dynamic>),
      load: () => _cache.store.eventDetail(id),
    );
    _details[id] = event;
    return event;
  }

  /// The event's page if it was opened earlier in this session, to show while
  /// [detail] fetches the live one (which also records the view).
  CampusEvent? recentDetail(int id) => _details[id];

  /// Records the student at the event, from the code in its QR. With the
  /// phone's position, the backend also checks they are near the venue.
  /// Throws [ApiException] with the backend's reason when it refuses (wrong
  /// code, outside the check-in window, too far away, cancelled).
  Future<CheckInResult> checkIn(
    int eventId, {
    required String code,
    double? latitude,
    double? longitude,
  }) async {
    _details.remove(eventId);
    return CheckInResult.fromJson(
      await _api.post(
            '/events/$eventId/check-in',
            body: {
              'code': code,
              'latitude': ?latitude,
              'longitude': ?longitude,
            },
          )
          as Map<String, dynamic>,
    );
  }

  /// The QR code for organizers to show at the venue. Only the group's admins
  /// get it; anyone else gets a 403 [ApiException].
  ///
  /// Kept on the phone: an event's code never changes, and the venue is
  /// exactly where the organizer may have no signal.
  Future<CheckInCode> checkInCode(int eventId) {
    final key = 'check_in_code:$eventId';
    return _cache.networkFirst(
      key,
      fetch: () => _api.get('/events/$eventId/check-in-code'),
      parse: (json) => CheckInCode.fromJson(json! as Map<String, dynamic>),
      save: (json) => _cache.store.saveDocument(key, json),
      load: () => _cache.store.document(key),
    );
  }

  /// How many events of the student's groups since [since] they checked in
  /// to. Walks every page, since a semester holds more than one.
  Future<int> attendedSince(DateTime since) {
    const key = attendedKey;
    return _cache.networkFirst(
      key,
      fetch: () => _countAttended(since),
      parse: (json) => json! as int,
      save: (json) => _cache.store.saveDocument(key, json),
      load: () => _cache.store.document(key),
    );
  }

  Future<int> _countAttended(DateTime since) async {
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

  static List<CampusEvent> _events(Object? json) => [
    for (final item in json! as List)
      CampusEvent.fromJson(item as Map<String, dynamic>),
  ];
}
