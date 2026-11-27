import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class PendingCover {
  const PendingCover({
    required this.groupId,
    required this.bytes,
    required this.savedAt,
  });

  final int groupId;
  final Uint8List bytes;
  final DateTime savedAt;
}

abstract interface class CoverOutboxStore {
  Future<void> put(String account, int groupId, Uint8List bytes);
  Future<PendingCover?> read(String account, int groupId);
  Future<List<PendingCover>> pending(String account);
  Future<void> remove(String account, int groupId);
}

String _account(String account) {
  final value = account.trim().toLowerCase();
  if (value.isEmpty) throw ArgumentError('An account is required.');
  return value;
}

class MemoryCoverOutboxStore implements CoverOutboxStore {
  final _covers = <(String, int), PendingCover>{};

  @override
  Future<void> put(String account, int groupId, Uint8List bytes) async {
    _covers[(_account(account), groupId)] = PendingCover(
      groupId: groupId,
      bytes: bytes,
      savedAt: DateTime.now(),
    );
  }

  @override
  Future<PendingCover?> read(String account, int groupId) async =>
      _covers[(_account(account), groupId)];

  @override
  Future<List<PendingCover>> pending(String account) async {
    final owner = _account(account);
    final covers = [
      for (final entry in _covers.entries)
        if (entry.key.$1 == owner) entry.value,
    ];
    covers.sort((a, b) => a.savedAt.compareTo(b.savedAt));
    return covers;
  }

  @override
  Future<void> remove(String account, int groupId) async {
    _covers.remove((_account(account), groupId));
  }
}

class SqliteCoverOutboxStore implements CoverOutboxStore {
  SqliteCoverOutboxStore({DatabaseFactory? factory, String? databasePath})
    : _factory = factory ?? databaseFactory,
      _path = databasePath;

  final DatabaseFactory _factory;
  final String? _path;
  Future<Database>? _opening;

  Future<Database> _database() => _opening ??= _open();

  Future<Database> _open() async {
    try {
      final location =
          _path ??
          path.join(await _factory.getDatabasesPath(), 'cover_outbox_v1.db');
      return await _factory.openDatabase(
        location,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute(
            'CREATE TABLE pending_covers ('
            'account TEXT NOT NULL, group_id INTEGER NOT NULL, '
            'bytes BLOB NOT NULL, saved_at INTEGER NOT NULL, '
            'PRIMARY KEY (account, group_id))',
          ),
        ),
      );
    } on Object {
      _opening = null;
      rethrow;
    }
  }

  PendingCover _cover(Map<String, Object?> row) => PendingCover(
    groupId: row['group_id'] as int,
    bytes: Uint8List.fromList(row['bytes'] as List<int>),
    savedAt: DateTime.fromMillisecondsSinceEpoch(row['saved_at'] as int),
  );

  @override
  Future<void> put(String account, int groupId, Uint8List bytes) async {
    final db = await _database();
    await db.insert('pending_covers', {
      'account': _account(account),
      'group_id': groupId,
      'bytes': bytes,
      'saved_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<PendingCover?> read(String account, int groupId) async {
    final db = await _database();
    final rows = await db.query(
      'pending_covers',
      where: 'account = ? AND group_id = ?',
      whereArgs: [_account(account), groupId],
    );
    return rows.isEmpty ? null : _cover(rows.single);
  }

  @override
  Future<List<PendingCover>> pending(String account) async {
    final db = await _database();
    final rows = await db.query(
      'pending_covers',
      where: 'account = ?',
      whereArgs: [_account(account)],
      orderBy: 'saved_at ASC',
    );
    return [for (final row in rows) _cover(row)];
  }

  @override
  Future<void> remove(String account, int groupId) async {
    final db = await _database();
    await db.delete(
      'pending_covers',
      where: 'account = ? AND group_id = ?',
      whereArgs: [_account(account), groupId],
    );
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}
