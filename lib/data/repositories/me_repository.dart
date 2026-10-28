import '../api/api_client.dart';
import '../local/offline_cache.dart';
import '../models/schedule_block.dart';
import '../models/student_profile.dart';

/// The signed-in student's own profile on the backend.
///
/// The profile and the schedule are kept on the phone, so the app still opens
/// (and Free right now still knows the classes) without a connection.
class MeRepository {
  MeRepository(this._api, {OfflineCache? cache})
    : _cache = cache ?? OfflineCache.disabled();

  final ApiClient _api;
  final OfflineCache _cache;

  static const profileKey = 'me';
  static const scheduleKey = 'schedule';

  /// The student's profile. The backend creates it on the first call after
  /// sign-in, so this is also what registers a new student.
  Future<StudentProfile> fetch() => _cache.networkFirst(
    profileKey,
    fetch: () => _api.get('/me'),
    parse: _profile,
    save: (json) => _cache.store.saveDocument(profileKey, json),
    load: () => _cache.store.document(profileKey),
  );

  /// Turns the use of the phone's location for suggestions on or off.
  Future<StudentProfile> setLocationOptIn(bool optIn) async {
    final session = _cache.sessionVersion;
    final json = await _api.patch('/me', body: {'location_opt_in': optIn});
    if (session == _cache.sessionVersion) {
      await _cache.keep(() => _cache.store.saveDocument(profileKey, json));
    }
    return _profile(json);
  }

  /// The weekly class schedule.
  Future<List<ScheduleBlock>> schedule() => _cache.networkFirst(
    scheduleKey,
    fetch: () => _api.get('/me/schedule'),
    parse: _blocks,
    save: (json) => _cache.store.saveDocument(scheduleKey, json),
    load: () => _cache.store.document(scheduleKey),
  );

  /// Replaces the whole schedule with [blocks]; returns it as saved.
  Future<List<ScheduleBlock>> saveSchedule(List<ScheduleBlock> blocks) async {
    final session = _cache.sessionVersion;
    final json = await _api.put(
      '/me/schedule',
      body: {
        'blocks': [for (final b in blocks) b.toJson()],
      },
    );
    if (session == _cache.sessionVersion) {
      await _cache.keep(() => _cache.store.saveDocument(scheduleKey, json));
    }
    return _blocks(json);
  }

  static StudentProfile _profile(Object? json) =>
      StudentProfile.fromJson(json as Map<String, dynamic>);

  static List<ScheduleBlock> _blocks(Object? json) => [
    for (final item in json as List)
      ScheduleBlock.fromJson(item as Map<String, dynamic>),
  ];
}
