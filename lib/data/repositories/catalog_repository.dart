import '../api/api_client.dart';
import '../local/offline_cache.dart';
import '../models/catalog.dart';

/// Reference lists that rarely change: interests and buildings. Fetched once
/// per launch and kept in memory; also kept on the phone, so the filters, the
/// schedule editor and leave reminders work offline.
class CatalogRepository {
  CatalogRepository(this._api, {OfflineCache? cache})
    : _cache = cache ?? OfflineCache.disabled();

  final ApiClient _api;
  final OfflineCache _cache;

  Future<List<Interest>>? _interests;
  Future<List<Building>>? _buildings;

  /// Every interest, alphabetically.
  Future<List<Interest>> interests() async {
    try {
      final interests = await (_interests ??= _fetch(
        'interests',
        '/interests',
        Interest.fromJson,
      ));
      // The phone's copy is only kept until the backend answers again.
      if (_cache.freshness.cachedAt('interests') != null) _interests = null;
      return interests;
    } on Object {
      _interests = null; // Not cached, so the next call tries again.
      rethrow;
    }
  }

  /// Every campus building, by code.
  Future<List<Building>> buildings() async {
    try {
      final buildings = await (_buildings ??= _fetch(
        'buildings',
        '/buildings',
        Building.fromJson,
      ));
      if (_cache.freshness.cachedAt('buildings') != null) _buildings = null;
      return buildings;
    } on Object {
      _buildings = null;
      rethrow;
    }
  }

  Future<List<T>> _fetch<T>(
    String key,
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) => _cache.networkFirst(
    key,
    fetch: () => _api.get(path),
    parse: (json) => [
      for (final item in json! as List) fromJson(item as Map<String, dynamic>),
    ],
    save: (json) => _cache.store.saveDocument(key, json),
    load: () => _cache.store.document(key),
  );
}
