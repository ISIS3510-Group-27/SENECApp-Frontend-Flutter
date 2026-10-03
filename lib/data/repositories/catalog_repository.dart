import '../api/api_client.dart';
import '../models/catalog.dart';

/// Reference lists that rarely change: interests and buildings. Fetched once
/// per launch and kept.
class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  Future<List<Interest>>? _interests;
  Future<List<Building>>? _buildings;

  /// Every interest, alphabetically.
  Future<List<Interest>> interests() async {
    try {
      return await (_interests ??= _fetch('/interests', Interest.fromJson));
    } on Object {
      _interests = null; // Not cached, so the next call tries again.
      rethrow;
    }
  }

  /// Every campus building, by code.
  Future<List<Building>> buildings() async {
    try {
      return await (_buildings ??= _fetch('/buildings', Building.fromJson));
    } on Object {
      _buildings = null;
      rethrow;
    }
  }

  Future<List<T>> _fetch<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) async => [
    for (final item in await _api.get(path) as List)
      fromJson(item as Map<String, dynamic>),
  ];
}
