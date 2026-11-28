import 'dart:convert';

import 'package:hive/hive.dart';

class StoredHealth {
  const StoredHealth({required this.body, required this.savedAt});

  final Map<String, dynamic> body;
  final DateTime savedAt;
}

abstract interface class HealthStore {
  Future<StoredHealth?> read(String account, int groupId);
  Future<void> write(
    String account,
    int groupId,
    Map<String, dynamic> body,
    DateTime at,
  );
  Future<void> remove(String account, int groupId);
}

String _key(String account, int groupId) =>
    '${account.trim().toLowerCase()}|$groupId';

class MemoryHealthStore implements HealthStore {
  final _rows = <String, String>{};

  @override
  Future<StoredHealth?> read(String account, int groupId) async =>
      _decode(_rows[_key(account, groupId)]);

  @override
  Future<void> write(
    String account,
    int groupId,
    Map<String, dynamic> body,
    DateTime at,
  ) async {
    _rows[_key(account, groupId)] = _encode(body, at);
  }

  @override
  Future<void> remove(String account, int groupId) async {
    _rows.remove(_key(account, groupId));
  }
}

class HiveHealthStore implements HealthStore {
  HiveHealthStore({Future<Box<String>> Function()? open})
    : _open = open ?? (() => Hive.openBox<String>(boxName));

  static const boxName = 'group_health';

  final Future<Box<String>> Function() _open;
  Future<Box<String>>? _box;

  Future<Box<String>> _boxReady() => _box ??= _openSafely();

  Future<Box<String>> _openSafely() async {
    try {
      return await _open();
    } on Object {
      _box = null;
      rethrow;
    }
  }

  @override
  Future<StoredHealth?> read(String account, int groupId) async {
    final box = await _boxReady();
    final key = _key(account, groupId);
    final stored = _decode(box.get(key));
    if (stored == null && box.containsKey(key)) await box.delete(key);
    return stored;
  }

  @override
  Future<void> write(
    String account,
    int groupId,
    Map<String, dynamic> body,
    DateTime at,
  ) async {
    final box = await _boxReady();
    await box.put(_key(account, groupId), _encode(body, at));
  }

  @override
  Future<void> remove(String account, int groupId) async {
    final box = await _boxReady();
    await box.delete(_key(account, groupId));
  }
}

String _encode(Map<String, dynamic> body, DateTime at) =>
    jsonEncode({'saved_at': at.toIso8601String(), 'body': body});

StoredHealth? _decode(String? text) {
  if (text == null) return null;
  try {
    final json = jsonDecode(text) as Map<String, dynamic>;
    return StoredHealth(
      body: json['body'] as Map<String, dynamic>,
      savedAt: DateTime.parse(json['saved_at'] as String),
    );
  } on Object {
    return null;
  }
}
