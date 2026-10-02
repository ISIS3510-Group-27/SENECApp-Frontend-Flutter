import '../api/api_client.dart';
import '../models/app_notification.dart';

/// The student's notification inbox on the backend.
///
/// Opening and dismissing are what BQ8 measures: which notification types get
/// interaction and which get cleared without a look.
class NotificationsRepository {
  const NotificationsRepository(this._api);

  final ApiClient _api;

  /// The most recent notifications, newest first.
  Future<List<AppNotification>> list({int limit = 50}) async {
    final json =
        await _api.get('/me/notifications', query: {'limit': limit})
            as Map<String, dynamic>;
    return [
      for (final item in json['items'] as List)
        AppNotification.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// The student tapped it.
  Future<void> open(int id) => _api.post('/me/notifications/$id/open');

  /// The student cleared it without opening it.
  Future<void> dismiss(int id) => _api.post('/me/notifications/$id/dismiss');
}
