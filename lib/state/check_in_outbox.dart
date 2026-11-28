import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api/api_client.dart';
import '../data/models/check_in.dart';
import '../data/repositories/events_repository.dart';

/// Durable, account-scoped attendance waiting for a connection.
class CheckInOutbox {
  CheckInOutbox({
    required this.account,
    required this.events,
    required this.preferences,
    required this.onCheckedIn,
    required Stream<void> reconnected,
  }) {
    _subscription = reconnected.listen((_) => _resume());
  }

  final String account;
  final EventsRepository events;
  final SharedPreferences? preferences;
  final void Function() onCheckedIn;
  late final StreamSubscription<void> _subscription;
  final _changes =
      StreamController<(int, CheckInResult?, ApiException?)>.broadcast();
  Stream<(int, CheckInResult?, ApiException?)> get changes => _changes.stream;
  final Map<int, Map<String, dynamic>> _pending = {};
  Future<void> _serial = Future.value();
  bool _disposed = false;
  String get _key => 'check_in.outbox.${account.toLowerCase()}';

  Future<void> start() async {
    final raw = preferences?.getString(_key);
    if (raw != null) {
      final rows = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in rows.entries) {
        _pending[int.parse(entry.key)] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
    }
    await _resume();
  }

  Future<void> _resume() async {
    try {
      await flush();
    } on Object catch (error) {
      debugPrint('Check-in outbox: $error');
    }
  }

  Future<void> _save() async {
    final ok = await preferences?.setString(
      _key,
      jsonEncode({
        for (final entry in _pending.entries) '${entry.key}': entry.value,
      }),
    );
    if (ok == false) {
      throw const ApiException(507, 'Could not save the pending check-in.');
    }
  }

  Future<T> _run<T>(Future<T> Function() action) {
    final result = _serial.then((_) => action());
    _serial = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<CheckInResult> submit(
    int id, {
    required String code,
    double? latitude,
    double? longitude,
  }) => _run(() async {
    if (_disposed) throw const ApiException(401, 'Session changed.');
    _pending[id] = {'code': code, 'latitude': latitude, 'longitude': longitude};
    await _save();
    return _send(id);
  });

  Future<CheckInResult> _send(int id) async {
    if (_disposed) throw const ApiException(401, 'Session changed.');
    final row = _pending[id]!;
    try {
      final result = await events.checkIn(
        id,
        code: row['code'] as String,
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
      );
      if (_disposed) return result;
      _pending.remove(id);
      await _save();
      if (_disposed) return result;
      onCheckedIn();
      _changes.add((id, result, null));
      return result;
    } on ApiException catch (e) {
      if (!_disposed && !e.isUnreachable) {
        _pending.remove(id);
        await _save();
        _changes.add((id, null, e));
      }
      rethrow;
    }
  }

  Future<void> flush() => _run(() async {
    for (final id in _pending.keys.toList()) {
      if (_disposed) return;
      try {
        await _send(id);
      } on ApiException catch (e) {
        if (e.isUnreachable) return;
      }
    }
  });

  Future<void> cancel(int id) => _run(() async {
    _pending.remove(id);
    await _save();
  });

  void dispose() {
    _disposed = true;
    _subscription.cancel();
    _changes.close();
  }
}
