import '../api/api_client.dart';
import '../models/recommendation.dart';

/// The backend's recommender.
class RecommendationsRepository {
  const RecommendationsRepository(this._api);

  final ApiClient _api;

  /// Groups ranked for the student by interests, schedule fit, proximity and
  /// popularity, leaving out the ones they already belong to.
  ///
  /// Each call is logged as the list being shown, so fetch once per visit and
  /// reuse the answer.
  Future<GroupRecommendations> groups({int limit = 10}) async =>
      GroupRecommendations.fromJson(
        await _api.get('/recommendations/groups', query: {'limit': limit})
            as Map<String, dynamic>,
      );
}
