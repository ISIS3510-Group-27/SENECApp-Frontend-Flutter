import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/event_draft.dart';

/// One draft per account and group. Separate from the disposable read cache.
abstract interface class EventDraftStore {
  Future<EventDraft?> read(String account, int groupId);
  Future<void> write(String account, int groupId, EventDraft draft);
  Future<void> remove(String account, int groupId);
}

String _account(String account) {
  final value = account.trim().toLowerCase();
  if (value.isEmpty) throw ArgumentError('An account is required.');
  return value;
}

class MemoryEventDraftStore implements EventDraftStore {
  final _drafts = <(String, int), EventDraft>{};

  @override
  Future<EventDraft?> read(String account, int groupId) async =>
      _drafts[(_account(account), groupId)];

  @override
  Future<void> write(String account, int groupId, EventDraft draft) async {
    _drafts[(_account(account), groupId)] = draft;
  }

  @override
  Future<void> remove(String account, int groupId) async {
    _drafts.remove((_account(account), groupId));
  }
}

/// Mobile drafts are committed to SQLite before the UI confirms a save.
class SqliteEventDraftStore implements EventDraftStore {
  SqliteEventDraftStore({DatabaseFactory? factory, String? databasePath})
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
          path.join(await _factory.getDatabasesPath(), 'event_drafts_v1.db');
      return await _factory.openDatabase(
        location,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute(
            'CREATE TABLE event_drafts ('
            'account TEXT NOT NULL, group_id INTEGER NOT NULL, '
            'body TEXT NOT NULL, PRIMARY KEY (account, group_id))',
          ),
        ),
      );
    } on Object {
      _opening = null;
      rethrow;
    }
  }

  @override
  Future<EventDraft?> read(String account, int groupId) async {
    final db = await _database();
    final rows = await db.query(
      'event_drafts',
      columns: ['body'],
      where: 'account = ? AND group_id = ?',
      whereArgs: [_account(account), groupId],
    );
    return rows.isEmpty
        ? null
        : EventDraft.fromJson(
            jsonDecode(rows.single['body'] as String) as Map<String, dynamic>,
          );
  }

  @override
  Future<void> write(String account, int groupId, EventDraft draft) async {
    final db = await _database();
    await db.insert('event_drafts', {
      'account': _account(account),
      'group_id': groupId,
      'body': jsonEncode(draft.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> remove(String account, int groupId) async {
    final db = await _database();
    await db.delete(
      'event_drafts',
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

/// Browser fallback; mobile uses SQLite, not preferences, for draft durability.
class PrefsEventDraftStore implements EventDraftStore {
  const PrefsEventDraftStore(this.preferences);

  final SharedPreferences preferences;

  String _key(String account, int groupId) =>
      'event_draft.v1.${Uri.encodeComponent(_account(account))}.$groupId';

  @override
  Future<EventDraft?> read(String account, int groupId) async {
    final raw = preferences.getString(_key(account, groupId));
    return raw == null
        ? null
        : EventDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(String account, int groupId, EventDraft draft) async {
    if (!await preferences.setString(
      _key(account, groupId),
      jsonEncode(draft.toJson()),
    )) {
      throw StateError('Draft could not be saved.');
    }
  }

  @override
  Future<void> remove(String account, int groupId) async {
    if (!await preferences.remove(_key(account, groupId))) {
      throw StateError('Draft could not be removed.');
    }
  }
}
