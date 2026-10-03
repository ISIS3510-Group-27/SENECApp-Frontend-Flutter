import '../api/api_client.dart';
import '../models/schedule_block.dart';
import '../models/student_profile.dart';

/// The signed-in student's own profile on the backend.
class MeRepository {
  const MeRepository(this._api);

  final ApiClient _api;

  /// The student's profile. The backend creates it on the first call after
  /// sign-in, so this is also what registers a new student.
  Future<StudentProfile> fetch() async =>
      StudentProfile.fromJson(await _api.get('/me') as Map<String, dynamic>);

  /// Turns the use of the phone's location for suggestions on or off.
  Future<StudentProfile> setLocationOptIn(bool optIn) async =>
      StudentProfile.fromJson(
        await _api.patch('/me', body: {'location_opt_in': optIn})
            as Map<String, dynamic>,
      );

  /// The weekly class schedule.
  Future<List<ScheduleBlock>> schedule() async =>
      _blocks(await _api.get('/me/schedule'));

  /// Replaces the whole schedule with [blocks]; returns it as saved.
  Future<List<ScheduleBlock>> saveSchedule(List<ScheduleBlock> blocks) async =>
      _blocks(
        await _api.put(
          '/me/schedule',
          body: {
            'blocks': [for (final b in blocks) b.toJson()],
          },
        ),
      );

  static List<ScheduleBlock> _blocks(Object? json) => [
    for (final item in json as List)
      ScheduleBlock.fromJson(item as Map<String, dynamic>),
  ];
}
