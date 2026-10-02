import '../api/api_client.dart';
import '../models/student_profile.dart';

/// The signed-in student's own profile on the backend.
class MeRepository {
  const MeRepository(this._api);

  final ApiClient _api;

  /// The student's profile. The backend creates it on the first call after
  /// sign-in, so this is also what registers a new student.
  Future<StudentProfile> fetch() async =>
      StudentProfile.fromJson(await _api.get('/me') as Map<String, dynamic>);
}
