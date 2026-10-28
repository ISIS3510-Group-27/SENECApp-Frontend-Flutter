import '../api/api_client.dart';
import '../local/offline_cache.dart';
import '../models/app_notification.dart';

/// The student's notification inbox on the backend.
///
/// Opening and dismissing are what BQ8 measures: which notification types get
/// interaction and which get cleared without a look.
///
/// The inbox is kept on the phone, so it can still be read offline.
class NotificationsRepository {
  NotificationsRepository(this._api, {OfflineCache? cache})
    : _cache = cache ?? OfflineCache.disabled();

  final ApiClient _api;
  final OfflineCache _cache;

  static const inboxKey = 'notifications';

  /// The most recent notifications, newest first.
  Future<List<AppNotification>> list({int limit = 50}) => _cache.networkFirst(
    inboxKey,
    fetch: () async =>
        (await _api.get('/me/notifications', query: {'limit': limit})
            as Map<String, dynamic>)['items'],
    parse: (json) => [
      for (final item in json! as List)
        AppNotification.fromJson(item as Map<String, dynamic>),
    ],
    save: (json) => _cache.store.saveNotifications(json! as List),
    load: () => _cache.store.notifications(),
  );

  /// The student tapped it.
  Future<void> open(int id) => _api.post('/me/notifications/$id/open');

  /// The student cleared it without opening it.
  Future<void> dismiss(int id) => _api.post('/me/notifications/$id/dismiss');

  /// Lets the backend push to this phone. [platform] is `android` or `ios`.
  Future<void> registerDevice(String token, {String? platform}) => _api.post(
    '/me/devices',
    body: {'token': token, 'platform': ?platform, 'app': 'flutter'},
  );

  /// Stops pushes to this phone for the signed-in student.
  Future<void> unregisterDevice(String token) =>
      _api.delete('/me/devices/${Uri.encodeComponent(token)}');
}
