import '../api/api_client.dart';
import '../models/free_now.dart';
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

  /// Events the student can make during their current or next free block,
  /// nearest and best matching first.
  ///
  /// [latitude] and [longitude] are only used by the backend if the student
  /// opted in to location; otherwise it goes by the building of their last or
  /// next class. Each call is logged as the suggestions being shown (BQ3).
  Future<FreeNowSuggestions> freeNow({
    double? latitude,
    double? longitude,
    int limit = 5,
  }) async => FreeNowSuggestions.fromJson(
    await _api.get(
          '/recommendations/events/free-now',
          query: {'latitude': latitude, 'longitude': longitude, 'limit': limit},
        )
        as Map<String, dynamic>,
  );
}
