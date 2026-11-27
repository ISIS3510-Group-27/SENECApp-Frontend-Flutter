import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/cache/ttl_cache.dart';
import '../api/api_client.dart';
import '../local/insight_store.dart';
import '../models/leader_insights.dart';

abstract final class InsightKeys {
  static String bestTimes(int groupId, Duration length) =>
      'insights:best-times:$groupId:${length.inMinutes}';

  static String audience(int groupId) => 'insights:audience:$groupId';

  static String profileTips(int groupId) => 'insights:profile:$groupId';
}

class InsightsRepository extends ChangeNotifier {
  InsightsRepository({
    required ApiClient api,
    required InsightStore store,
    DateTime Function()? clock,
  }) : _api = api,
       _store = store,
       _clock = clock ?? DateTime.now,
       _memory = TtlCache<String, Object>(
         capacity: memoryCapacity,
         ttl: memoryTtl,
         clock: clock,
       );

  static const memoryCapacity = 20;
  static const memoryTtl = Duration(seconds: 60);
  static const diskFreshFor = Duration(minutes: 15);
  static const keepFor = Duration(days: 7);

  final ApiClient _api;
  final InsightStore _store;
  final DateTime Function() _clock;
  final TtlCache<String, Object> _memory;
  final _copies = <String, DateTime>{};
  String? _account;

  void useAccount(String? account) {
    final next = account?.trim().toLowerCase();
    if (next == _account) return;
    _account = next;
    _memory.clear();
    _copies.clear();
  }

  DateTime? copySavedAt(String key) => _copies[key];

  Future<BestTimes> bestTimes(
    int groupId, {
    required Duration length,
    bool force = false,
  }) => _load<BestTimes>(
    InsightKeys.bestTimes(groupId, length),
    force: force,
    fetch: () => _api.get(
      '/groups/$groupId/insights/best-times',
      query: {'duration_minutes': length.inMinutes},
    ),
    parse: (json) => BestTimes.fromJson(
      json! as Map<String, dynamic>,
    ).upcoming(DateTime.now()),
  );

  Future<Audience> audience(int groupId, {bool force = false}) =>
      _load<Audience>(
        InsightKeys.audience(groupId),
        force: force,
        fetch: () => _api.get('/groups/$groupId/insights/audience'),
        parse: (json) => Audience.fromJson(json! as Map<String, dynamic>),
      );

  Future<ProfileTips> profileTips(int groupId, {bool force = false}) =>
      _load<ProfileTips>(
        InsightKeys.profileTips(groupId),
        force: force,
        fetch: () => _api.get('/groups/$groupId/insights/profile'),
        parse: (json) => ProfileTips.fromJson(json! as Map<String, dynamic>),
      );

  Future<void> forget(String key) async {
    _memory.remove(key);
    if (_copies.remove(key) != null) notifyListeners();
    final owner = _account;
    if (owner == null) return;
    try {
      await _store.remove(owner, key);
    } on Object catch (e) {
      debugPrint('Insight store: $e');
    }
  }

  Future<T> _load<T extends Object>(
    String key, {
    required Future<Object?> Function() fetch,
    required T Function(Object? json) parse,
    required bool force,
  }) async {
    final owner = _account;
    if (!force) {
      final kept = _memory[key];
      if (kept is T) return kept;
    }

    var stored = owner == null ? null : await _read(owner, key);
    final age = stored == null ? null : _clock().difference(stored.savedAt);
    if (stored != null && age! > keepFor) {
      stored = null;
      await forget(key);
    } else if (!force && stored != null && age! < diskFreshFor) {
      final value = _tryParse(parse, stored.body);
      if (value != null) {
        _memory[key] = value;
        _copies[key] = stored.savedAt;
        notifyListeners();
        return value;
      }
    }

    try {
      final json = await fetch();
      final value = parse(json);
      if (owner == _account) {
        _memory[key] = value;
        if (_copies.remove(key) != null) notifyListeners();
        if (owner != null) await _write(owner, key, json);
      }
      return value;
    } on ApiException catch (e) {
      if (!e.isUnreachable || stored == null || owner != _account) rethrow;
      final value = _tryParse(parse, stored.body);
      if (value == null) rethrow;
      _copies[key] = stored.savedAt;
      notifyListeners();
      return value;
    }
  }

  T? _tryParse<T extends Object>(T Function(Object? json) parse, Object? body) {
    try {
      return parse(body);
    } on Object {
      return null;
    }
  }

  Future<StoredInsight?> _read(String owner, String key) async {
    try {
      return await _store.read(owner, key);
    } on Object catch (e) {
      debugPrint('Insight store: $e');
      return null;
    }
  }

  Future<void> _write(String owner, String key, Object? json) async {
    try {
      await _store.write(owner, key, json, _clock());
    } on Object catch (e) {
      debugPrint('Insight store: $e');
    }
  }
}
