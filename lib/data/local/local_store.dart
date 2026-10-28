import 'package:flutter/foundation.dart';

/// A copy of something the backend sent, and when it was stored.
@immutable
class Cached<T> {
  const Cached(this.value, this.savedAt);

  final T value;
  final DateTime savedAt;
}

/// The phone's copy of what the student last saw, for when the backend can't
/// be reached.
///
/// Values are the backend's JSON, exactly as received: repositories parse them
/// the same way online and offline. Each account has its own copy, opened at
/// sign-in and deleted at sign-out, so a shared phone never shows one
/// student's groups or inbox to the next.
abstract interface class LocalStore {
  /// Opens [account]'s copy. Everything else is a no-op until then.
  Future<void> open(String account);

  /// Deletes the open account's copy (sign-out).
  Future<void> wipe();

  /// Replaces the list [name] (e.g. `mine`) with [groups], in order.
  Future<void> saveGroups(String name, List<Object?> groups);
  Future<Cached<List<Object?>>?> groups(String name);

  Future<void> saveGroupDetail(Map<String, dynamic> group);
  Future<Cached<Map<String, dynamic>>?> groupDetail(int id);

  /// Replaces the list [name] (`all` or `mine`) with [events], in order.
  Future<void> saveEvents(String name, List<Object?> events);
  Future<Cached<List<Object?>>?> events(String name);

  Future<void> saveEventDetail(Map<String, dynamic> event);
  Future<Cached<Map<String, dynamic>>?> eventDetail(int id);

  /// Applies a successful check-in to existing event summaries and details.
  Future<void> markEventCheckedIn(int id);

  /// Replaces the inbox.
  Future<void> saveNotifications(List<Object?> notifications);
  Future<Cached<List<Object?>>?> notifications();

  /// Single answers stored whole: the profile, the schedule, the catalog...
  Future<void> saveDocument(String key, Object? json);
  Future<Cached<Object?>?> document(String key);
}

/// Stores nothing: on the web (no SQLite there) and in tests that don't need
/// an offline copy.
class NoLocalStore implements LocalStore {
  const NoLocalStore();

  @override
  Future<void> open(String account) async {}

  @override
  Future<void> wipe() async {}

  @override
  Future<void> saveGroups(String name, List<Object?> groups) async {}

  @override
  Future<Cached<List<Object?>>?> groups(String name) async => null;

  @override
  Future<void> saveGroupDetail(Map<String, dynamic> group) async {}

  @override
  Future<Cached<Map<String, dynamic>>?> groupDetail(int id) async => null;

  @override
  Future<void> saveEvents(String name, List<Object?> events) async {}

  @override
  Future<Cached<List<Object?>>?> events(String name) async => null;

  @override
  Future<void> saveEventDetail(Map<String, dynamic> event) async {}

  @override
  Future<Cached<Map<String, dynamic>>?> eventDetail(int id) async => null;

  @override
  Future<void> markEventCheckedIn(int id) async {}

  @override
  Future<void> saveNotifications(List<Object?> notifications) async {}

  @override
  Future<Cached<List<Object?>>?> notifications() async => null;

  @override
  Future<void> saveDocument(String key, Object? json) async {}

  @override
  Future<Cached<Object?>?> document(String key) async => null;
}
