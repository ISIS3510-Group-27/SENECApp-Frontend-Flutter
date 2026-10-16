import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'local_store.dart';

/// [LocalStore] on a relational SQLite database (`sqflite`), one file per
/// account.
///
/// Groups and events are tables keyed by their backend id, so a group that is
/// both in "My RSOs" and opened on its own page is stored once. The lists the
/// app shows (My RSOs, the Explore page, all events, my events) are join
/// tables that keep each list's order, read back with a JOIN. Each row keeps
/// the backend's JSON as received plus the columns the queries need.
class SqliteLocalStore implements LocalStore {
  SqliteLocalStore({
    DatabaseFactory? factory,
    String? directory,
    DateTime Function()? clock,
  }) : _factory = factory ?? databaseFactory,
       _directory = directory,
       _clock = clock ?? DateTime.now;

  final DatabaseFactory _factory;
  final String? _directory;
  final DateTime Function() _clock;

  /// Rows no list points to anymore are dropped after this long, so groups
  /// and events opened once don't pile up forever.
  static const keepUnlisted = Duration(days: 14);

  static const _version = 1;

  Future<Database>? _db;
  String? _path;

  @override
  Future<void> open(String account) async {
    await _close();
    final directory = _directory ?? await _factory.getDatabasesPath();
    final path = p.join(directory, 'senecapp_${_fileKey(account)}.db');
    _path = path;
    _db = _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _createSchema(db),
        onOpen: _prune,
      ),
    );
    await _db;
  }

  @override
  Future<void> wipe() async {
    final path = _path;
    await _close();
    if (path != null) await _factory.deleteDatabase(path);
  }

  // --- Groups ---------------------------------------------------------------

  @override
  Future<void> saveGroups(String name, List<Object?> groups) =>
      _write((txn, now) async {
        final batch = txn.batch();
        for (final group in groups.cast<Map<String, dynamic>>()) {
          batch
            ..rawInsert(
              'INSERT OR IGNORE INTO groups (id, name, summary_json, saved_at) '
              'VALUES (?, ?, ?, ?)',
              [group['id'], group['name'], jsonEncode(group), now],
            )
            ..rawUpdate(
              'UPDATE groups SET name = ?, summary_json = ?, saved_at = ? '
              'WHERE id = ?',
              [group['name'], jsonEncode(group), now, group['id']],
            );
        }
        batch.delete('group_lists', where: 'list = ?', whereArgs: [name]);
        for (final (position, group) in groups.indexed) {
          batch.insert('group_lists', {
            'list': name,
            'position': position,
            'group_id': (group as Map<String, dynamic>)['id'],
          });
        }
        _markSaved(batch, 'groups:$name', now);
        await batch.commit(noResult: true);
      });

  @override
  Future<Cached<List<Object?>>?> groups(String name) => _readList(
    'groups:$name',
    'SELECT g.summary_json AS json FROM group_lists l '
        'JOIN groups g ON g.id = l.group_id '
        'WHERE l.list = ? ORDER BY l.position',
    [name],
  );

  @override
  Future<void> saveGroupDetail(Map<String, dynamic> group) =>
      _write((txn, now) async {
        final json = jsonEncode(group);
        // A detail is a summary plus more, so it can stand in for one.
        await txn.rawInsert(
          'INSERT OR IGNORE INTO groups (id, name, summary_json, saved_at) '
          'VALUES (?, ?, ?, ?)',
          [group['id'], group['name'], json, now],
        );
        await txn.rawUpdate(
          'UPDATE groups SET name = ?, detail_json = ?, detail_saved_at = ? '
          'WHERE id = ?',
          [group['name'], json, now, group['id']],
        );
      });

  @override
  Future<Cached<Map<String, dynamic>>?> groupDetail(int id) =>
      _readDetail('groups', id);

  // --- Events ---------------------------------------------------------------

  @override
  Future<void> saveEvents(String name, List<Object?> events) => _write((
    txn,
    now,
  ) async {
    final batch = txn.batch();
    for (final event in events.cast<Map<String, dynamic>>()) {
      final values = [
        event['group_id'],
        event['starts_at'],
        jsonEncode(event),
        now,
      ];
      batch
        ..rawInsert(
          'INSERT OR IGNORE INTO events '
          '(group_id, starts_at, summary_json, saved_at, id) '
          'VALUES (?, ?, ?, ?, ?)',
          [...values, event['id']],
        )
        ..rawUpdate(
          'UPDATE events SET group_id = ?, starts_at = ?, summary_json = ?, '
          'saved_at = ? WHERE id = ?',
          [...values, event['id']],
        );
    }
    batch.delete('event_lists', where: 'list = ?', whereArgs: [name]);
    for (final (position, event) in events.indexed) {
      batch.insert('event_lists', {
        'list': name,
        'position': position,
        'event_id': (event as Map<String, dynamic>)['id'],
      });
    }
    _markSaved(batch, 'events:$name', now);
    await batch.commit(noResult: true);
  });

  @override
  Future<Cached<List<Object?>>?> events(String name) => _readList(
    'events:$name',
    'SELECT e.summary_json AS json FROM event_lists l '
        'JOIN events e ON e.id = l.event_id '
        'WHERE l.list = ? ORDER BY l.position',
    [name],
  );

  @override
  Future<void> saveEventDetail(Map<String, dynamic> event) =>
      _write((txn, now) async {
        final json = jsonEncode(event);
        await txn.rawInsert(
          'INSERT OR IGNORE INTO events '
          '(id, group_id, starts_at, summary_json, saved_at) '
          'VALUES (?, ?, ?, ?, ?)',
          [event['id'], event['group_id'], event['starts_at'], json, now],
        );
        await txn.rawUpdate(
          'UPDATE events SET group_id = ?, starts_at = ?, detail_json = ?, '
          'detail_saved_at = ? WHERE id = ?',
          [event['group_id'], event['starts_at'], json, now, event['id']],
        );
      });

  @override
  Future<Cached<Map<String, dynamic>>?> eventDetail(int id) =>
      _readDetail('events', id);

  // --- Notifications and documents ------------------------------------------

  @override
  Future<void> saveNotifications(List<Object?> notifications) =>
      _write((txn, now) async {
        final batch = txn.batch()..delete('notifications');
        for (final (position, item) in notifications.indexed) {
          final notification = item as Map<String, dynamic>;
          batch.insert('notifications', {
            'id': notification['id'],
            'position': position,
            'json': jsonEncode(notification),
          });
        }
        _markSaved(batch, 'notifications', now);
        await batch.commit(noResult: true);
      });

  @override
  Future<Cached<List<Object?>>?> notifications() => _readList(
    'notifications',
    'SELECT json FROM notifications ORDER BY position',
    const [],
  );

  @override
  Future<void> saveDocument(String key, Object? json) =>
      _write((txn, now) async {
        await txn.insert('documents', {
          'key': key,
          'json': jsonEncode(json),
          'saved_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });

  @override
  Future<Cached<Object?>?> document(String key) async {
    final db = await _db;
    if (db == null) return null;
    final rows = await db.query(
      'documents',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return Cached(
      jsonDecode(rows.single['json']! as String),
      _time(rows.single['saved_at']),
    );
  }

  // --- Plumbing -------------------------------------------------------------

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE groups (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          summary_json TEXT NOT NULL,
          saved_at INTEGER NOT NULL,
          detail_json TEXT,
          detail_saved_at INTEGER
        )''')
      ..execute('''
        CREATE TABLE events (
          id INTEGER PRIMARY KEY,
          group_id INTEGER NOT NULL,
          starts_at TEXT NOT NULL,
          summary_json TEXT NOT NULL,
          saved_at INTEGER NOT NULL,
          detail_json TEXT,
          detail_saved_at INTEGER
        )''')
      ..execute('CREATE INDEX events_by_group ON events (group_id)')
      ..execute('''
        CREATE TABLE group_lists (
          list TEXT NOT NULL,
          position INTEGER NOT NULL,
          group_id INTEGER NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
          PRIMARY KEY (list, position)
        )''')
      ..execute('''
        CREATE TABLE event_lists (
          list TEXT NOT NULL,
          position INTEGER NOT NULL,
          event_id INTEGER NOT NULL REFERENCES events (id) ON DELETE CASCADE,
          PRIMARY KEY (list, position)
        )''')
      ..execute('''
        CREATE TABLE notifications (
          id INTEGER PRIMARY KEY,
          position INTEGER NOT NULL,
          json TEXT NOT NULL
        )''')
      ..execute('''
        CREATE TABLE documents (
          key TEXT PRIMARY KEY,
          json TEXT NOT NULL,
          saved_at INTEGER NOT NULL
        )''')
      // When each list was last replaced, for "saved at ..." when offline.
      ..execute('''
        CREATE TABLE snapshots (
          name TEXT PRIMARY KEY,
          saved_at INTEGER NOT NULL
        )''');
    await batch.commit(noResult: true);
  }

  /// Drops groups and events that no list points to and that haven't been
  /// refreshed for [keepUnlisted].
  Future<void> _prune(Database db) async {
    final cutoff = _clock().subtract(keepUnlisted).millisecondsSinceEpoch;
    await db.rawDelete(
      'DELETE FROM groups WHERE id NOT IN (SELECT group_id FROM group_lists) '
      'AND MAX(saved_at, IFNULL(detail_saved_at, 0)) < ?',
      [cutoff],
    );
    await db.rawDelete(
      'DELETE FROM events WHERE id NOT IN (SELECT event_id FROM event_lists) '
      'AND MAX(saved_at, IFNULL(detail_saved_at, 0)) < ?',
      [cutoff],
    );
  }

  Future<void> _write(
    Future<void> Function(Transaction txn, int now) action,
  ) async {
    final db = await _db;
    if (db == null) return;
    final now = _clock().millisecondsSinceEpoch;
    await db.transaction((txn) => action(txn, now));
  }

  Future<Cached<List<Object?>>?> _readList(
    String snapshot,
    String sql,
    List<Object?> args,
  ) async {
    final db = await _db;
    if (db == null) return null;
    final saved = await db.query(
      'snapshots',
      where: 'name = ?',
      whereArgs: [snapshot],
    );
    // Never stored, as opposed to stored empty.
    if (saved.isEmpty) return null;
    final rows = await db.rawQuery(sql, args);
    return Cached([
      for (final row in rows) jsonDecode(row['json']! as String),
    ], _time(saved.single['saved_at']));
  }

  Future<Cached<Map<String, dynamic>>?> _readDetail(
    String table,
    int id,
  ) async {
    final db = await _db;
    if (db == null) return null;
    final rows = await db.query(
      table,
      columns: ['detail_json', 'detail_saved_at'],
      where: 'id = ? AND detail_json IS NOT NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Cached(
      jsonDecode(rows.single['detail_json']! as String) as Map<String, dynamic>,
      _time(rows.single['detail_saved_at']),
    );
  }

  static void _markSaved(Batch batch, String name, int now) => batch.insert(
    'snapshots',
    {'name': name, 'saved_at': now},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  static DateTime _time(Object? millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis! as int);

  /// The account's email, reduced to characters safe in a file name.
  static String _fileKey(String account) =>
      account.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');

  Future<void> _close() async {
    final db = _db;
    _db = null;
    _path = null;
    if (db != null) await (await db).close();
  }
}
