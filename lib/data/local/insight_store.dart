import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class StoredInsight {
  const StoredInsight({required this.body, required this.savedAt});

  final Object? body;
  final DateTime savedAt;
}

abstract interface class InsightStore {
  Future<StoredInsight?> read(String account, String key);
  Future<void> write(String account, String key, Object? body, DateTime at);
  Future<void> remove(String account, String key);
}

String _owner(String account) {
  final value = account.trim().toLowerCase();
  if (value.isEmpty) throw ArgumentError('An account is required.');
  return value;
}

class MemoryInsightStore implements InsightStore {
  final _copies = <(String, String), StoredInsight>{};

  @override
  Future<StoredInsight?> read(String account, String key) async =>
      _copies[(_owner(account), key)];

  @override
  Future<void> write(
    String account,
    String key,
    Object? body,
    DateTime at,
  ) async {
    _copies[(_owner(account), key)] = StoredInsight(
      body: jsonDecode(jsonEncode(body)),
      savedAt: at,
    );
  }

  @override
  Future<void> remove(String account, String key) async {
    _copies.remove((_owner(account), key));
  }
}

class FileInsightStore implements InsightStore {
  FileInsightStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static String _name(String text) =>
      base64Url.encode(utf8.encode(text)).replaceAll('=', '');

  Future<File> _file(String account, String key) async {
    final root = await _directory();
    final folder = Directory(
      path.join(root.path, 'insights', _name(_owner(account))),
    );
    await folder.create(recursive: true);
    return File(path.join(folder.path, '${_name(key)}.json'));
  }

  @override
  Future<StoredInsight?> read(String account, String key) async {
    final file = await _file(account, key);
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      final decoded = await compute(_decode, text);
      return StoredInsight(
        body: decoded['body'],
        savedAt: DateTime.parse(decoded['saved_at'] as String),
      );
    } on Object {
      await _delete(file);
      return null;
    }
  }

  @override
  Future<void> write(
    String account,
    String key,
    Object? body,
    DateTime at,
  ) async {
    final file = await _file(account, key);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'saved_at': at.toIso8601String(), 'body': body}),
      flush: true,
    );
    await _delete(file);
    await temporary.rename(file.path);
  }

  @override
  Future<void> remove(String account, String key) async {
    await _delete(await _file(account, key));
  }

  static Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      return;
    }
  }

  static Map<String, dynamic> _decode(String text) =>
      jsonDecode(text) as Map<String, dynamic>;
}
