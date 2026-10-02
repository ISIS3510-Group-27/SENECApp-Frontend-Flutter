import '../api/api_client.dart';
import '../models/campus_event.dart';
import '../models/check_in.dart';
import '../models/entry_point.dart';

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

  /// One event's page. Each call is logged as a view (BQ3), so call it once
  /// per visit, with how the student got there.
  Future<CampusEvent> detail(
    int id, {
    required EventEntryPoint entryPoint,
    String? recRequestId,
  }) async => CampusEvent.fromJson(
    await _api.get(
          '/events/$id',
          query: {
            'entry_point': entryPoint.value,
            'rec_request_id': recRequestId,
          },
        )
        as Map<String, dynamic>,
  );

  /// Records the student at the event, from the code in its QR. With the
  /// phone's position, the backend also checks they are near the venue.
  /// Throws [ApiException] with the backend's reason when it refuses (wrong
  /// code, outside the check-in window, too far away, cancelled).
  Future<CheckInResult> checkIn(
    int eventId, {
    required String code,
    double? latitude,
    double? longitude,
  }) async => CheckInResult.fromJson(
    await _api.post(
          '/events/$eventId/check-in',
          body: {'code': code, 'latitude': ?latitude, 'longitude': ?longitude},
        )
        as Map<String, dynamic>,
  );

  /// The QR code for organizers to show at the venue. Only the group's admins
  /// get it; anyone else gets a 403 [ApiException].
  Future<CheckInCode> checkInCode(int eventId) async => CheckInCode.fromJson(
    await _api.get('/events/$eventId/check-in-code') as Map<String, dynamic>,
  );

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
