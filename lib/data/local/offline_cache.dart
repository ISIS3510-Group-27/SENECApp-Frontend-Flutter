import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'local_store.dart';

/// Which answers came from the phone's copy instead of the backend, and how
/// old that copy is. Screens use it to say "offline, saved at 10:42".
class DataFreshness extends ChangeNotifier {
  final Map<String, DateTime> _cached = {};

  /// When the copy shown for [key] was saved; `null` if it came live.
  DateTime? cachedAt(String key) => _cached[key];

  /// Whether anything on screen may be out of date.
  bool get anyCached => _cached.isNotEmpty;

  void _fresh(String key) {
    if (_cached.remove(key) != null) notifyListeners();
  }

  void _fromCache(String key, DateTime savedAt) {
    if (_cached[key] == savedAt) return;
    _cached[key] = savedAt;
    notifyListeners();
  }

  /// Forgets everything (sign-out).
  void reset() {
    if (_cached.isEmpty) return;
    _cached.clear();
    notifyListeners();
  }
}

/// The read strategy repositories share: network first, the stored copy when
/// the backend can't be reached.
///
/// A live answer is shown and stored for next time. When the phone is offline,
/// or the backend is down (5xx), the last stored answer is shown instead and
/// [freshness] remembers how old it is. Any other refusal (403, 404, 422) is
/// the backend's real answer and is passed on: a stale copy would hide it.
class OfflineCache {
  OfflineCache({required this.store, DataFreshness? freshness})
    : freshness = freshness ?? DataFreshness();

  /// Stores nothing: every read goes to the backend, as before.
  OfflineCache.disabled() : this(store: const NoLocalStore());

  final LocalStore store;
  final DataFreshness freshness;

  int _sessionVersion = 0;

  /// Identifies the account lifetime, including requests still in flight.
  int get sessionVersion => _sessionVersion;

  /// Old responses must not populate the next account's disk or memory cache.
  void resetSession() {
    _sessionVersion++;
    freshness.reset();
  }

  Future<T> networkFirst<T>(
    String key, {
    required Future<Object?> Function() fetch,
    required T Function(Object? json) parse,
    required Future<void> Function(Object? json) save,
    required Future<Cached<Object?>?> Function() load,
  }) async {
    final session = _sessionVersion;
    final Object? json;
    try {
      json = await fetch();
    } on ApiException catch (e, stack) {
      if (!e.isUnreachable || session != _sessionVersion) rethrow;
      final cached = await _quietly(load);
      if (cached == null || session != _sessionVersion) rethrow;
      final T value;
      try {
        value = parse(cached.value);
      } on Object {
        // A copy from an older app version that no longer parses is no copy.
        Error.throwWithStackTrace(e, stack);
      }
      freshness._fromCache(key, cached.savedAt);
      return value;
    }
    final value = parse(json);
    if (session != _sessionVersion) return value;
    freshness._fresh(key);
    // A full disk or a broken file must never cost the student a live answer.
    await _quietly(() => save(json));
    return value;
  }

  /// Stores a live answer that didn't come from a read (what an edit returns),
  /// without ever failing the edit.
  Future<void> keep(Future<void> Function() save) => _quietly(save);

  static Future<R?> _quietly<R>(Future<R?> Function() action) async {
    try {
      return await action();
    } on Object catch (e) {
      debugPrint('Offline cache: $e');
      return null;
    }
  }
}
