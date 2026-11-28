import 'package:flutter/foundation.dart';

import '../../core/cache/ttl_cache.dart';
import '../api/api_client.dart';
import '../local/health_store.dart';
import '../models/group_health.dart';

class HealthResult {
  const HealthResult({required this.health, this.savedAt});

  final GroupHealth health;
  final DateTime? savedAt;

  bool get fromCopy => savedAt != null;
}

class GroupHealthRepository {
  GroupHealthRepository({
    required ApiClient api,
    required HealthStore store,
    DateTime Function()? clock,
  }) : _api = api,
       _store = store,
       _clock = clock ?? DateTime.now,
       _memory = TtlCache<int, HealthResult>(
         capacity: memoryCapacity,
         ttl: memoryTtl,
         clock: clock,
       );

  static const memoryCapacity = 10;
  static const memoryTtl = Duration(minutes: 2);
  static const diskFreshFor = Duration(minutes: 30);
  static const keepFor = Duration(days: 14);

  final ApiClient _api;
  final HealthStore _store;
  final DateTime Function() _clock;
  final TtlCache<int, HealthResult> _memory;
  String? _account;

  void useAccount(String? account) {
    final next = account?.trim().toLowerCase();
    if (next == _account) return;
    _account = next;
    _memory.clear();
  }

  Future<HealthResult> load(int groupId, {bool force = false}) async {
    final owner = _account;
    if (!force) {
      final kept = _memory[groupId];
      if (kept != null) return kept;
    }

    var stored = owner == null ? null : await _read(owner, groupId);
    if (stored != null) {
      final age = _clock().difference(stored.savedAt);
      if (age > keepFor) {
        await _remove(owner!, groupId);
        stored = null;
      } else if (!force && age < diskFreshFor) {
        final copy = _parse(stored);
        if (copy != null) {
          _memory[groupId] = copy;
          return copy;
        }
      }
    }

    try {
      final json = await _api.get('/groups/$groupId/insights/health');
      final body = json! as Map<String, dynamic>;
      final result = HealthResult(health: GroupHealth.fromJson(body));
      if (owner == _account) {
        _memory[groupId] = result;
        if (owner != null) await _write(owner, groupId, body);
      }
      return result;
    } on ApiException catch (e) {
      if (!e.isUnreachable || stored == null || owner != _account) rethrow;
      final copy = _parse(stored);
      if (copy == null) rethrow;
      return copy;
    }
  }

  HealthResult? _parse(StoredHealth stored) {
    try {
      return HealthResult(
        health: GroupHealth.fromJson(stored.body),
        savedAt: stored.savedAt,
      );
    } on Object {
      return null;
    }
  }

  Future<StoredHealth?> _read(String owner, int groupId) async {
    try {
      return await _store.read(owner, groupId);
    } on Object catch (e) {
      debugPrint('Health store: $e');
      return null;
    }
  }

  Future<void> _write(
    String owner,
    int groupId,
    Map<String, dynamic> body,
  ) async {
    try {
      await _store.write(owner, groupId, body, _clock());
    } on Object catch (e) {
      debugPrint('Health store: $e');
    }
  }

  Future<void> _remove(String owner, int groupId) async {
    try {
      await _store.remove(owner, groupId);
    } on Object catch (e) {
      debugPrint('Health store: $e');
    }
  }
}
