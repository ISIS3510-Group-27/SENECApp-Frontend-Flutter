import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/join_sources.dart';

/// The answers a leader saw on "Where your members come from", per account
/// and group, so the screen opens offline and can say what changed since the
/// previous visit.
abstract interface class JoinHistoryStore {
  /// Newest first, at most [limit].
  Future<List<JoinSnapshot>> recent(String account, int groupId, {int limit});

  /// Saves [snapshot]. A snapshot taken within [JoinHistoryStore.mergeWithin]
  /// of the newest one replaces it, so refreshing doesn't fill the history
  /// with copies of the same answer; older history beyond
  /// [JoinHistoryStore.keep] snapshots is dropped.
  Future<void> add(String account, int groupId, JoinSnapshot snapshot);

  Future<void> clear(String account);

  static const keep = 12;
  static const mergeWithin = Duration(hours: 6);
}

String _account(String account) {
  final value = account.trim().toLowerCase();
  if (value.isEmpty) throw ArgumentError('An account is required.');
  return value;
}

class MemoryJoinHistoryStore implements JoinHistoryStore {
  final _history = <(String, int), List<JoinSnapshot>>{};

  @override
  Future<List<JoinSnapshot>> recent(
    String account,
    int groupId, {
    int limit = JoinHistoryStore.keep,
  }) async =>
      (_history[(_account(account), groupId)] ?? const []).take(limit).toList();

  @override
  Future<void> add(String account, int groupId, JoinSnapshot snapshot) async {
    final list = _history.putIfAbsent((_account(account), groupId), () => []);
    if (list.isNotEmpty &&
        snapshot.takenAt.difference(list.first.takenAt) <
            JoinHistoryStore.mergeWithin) {
      list.removeAt(0);
    }
    list.insert(0, snapshot);
    if (list.length > JoinHistoryStore.keep) {
      list.removeRange(JoinHistoryStore.keep, list.length);
    }
  }

  @override
  Future<void> clear(String account) async {
    final owner = _account(account);
    _history.removeWhere((key, _) => key.$1 == owner);
  }
}

/// [JoinHistoryStore] on two related SQLite tables: one row per snapshot
/// (`join_snapshots`) and one row per entry point in it
/// (`join_snapshot_sources`, foreign key with `ON DELETE CASCADE`). Keeping the
/// entry points as rows, not one JSON blob, lets "what changed" be read with a
/// query and lets pruning a snapshot remove its sources in the same statement.
class SqliteJoinHistoryStore implements JoinHistoryStore {
  SqliteJoinHistoryStore({DatabaseFactory? factory, String? databasePath})
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
          path.join(await _factory.getDatabasesPath(), 'join_history_v1.db');
      return await _factory.openDatabase(
        location,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE join_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account TEXT NOT NULL,
                group_id INTEGER NOT NULL,
                taken_at INTEGER NOT NULL,
                days INTEGER NOT NULL,
                views INTEGER NOT NULL,
                joins INTEGER NOT NULL,
                question TEXT NOT NULL,
                answer TEXT NOT NULL,
                campus_answer TEXT NOT NULL
              )''');
            await db.execute(
              'CREATE INDEX join_snapshots_by_group '
              'ON join_snapshots (account, group_id, taken_at DESC)',
            );
            await db.execute('''
              CREATE TABLE join_snapshot_sources (
                snapshot_id INTEGER NOT NULL
                  REFERENCES join_snapshots (id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                entry_point TEXT NOT NULL,
                views INTEGER NOT NULL,
                joins INTEGER NOT NULL,
                view_to_join_rate REAL,
                share_of_joins REAL,
                campus_view_to_join_rate REAL,
                PRIMARY KEY (snapshot_id, entry_point)
              )''');
          },
        ),
      );
    } on Object {
      _opening = null;
      rethrow;
    }
  }

  @override
  Future<List<JoinSnapshot>> recent(
    String account,
    int groupId, {
    int limit = JoinHistoryStore.keep,
  }) async {
    final db = await _database();
    final snapshots = await db.query(
      'join_snapshots',
      where: 'account = ? AND group_id = ?',
      whereArgs: [_account(account), groupId],
      orderBy: 'taken_at DESC',
      limit: limit,
    );
    if (snapshots.isEmpty) return const [];
    final ids = [for (final row in snapshots) row['id']! as int];
    final sources = await db.query(
      'join_snapshot_sources',
      where: 'snapshot_id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
      orderBy: 'snapshot_id, position',
    );
    final bySnapshot = <int, List<JoinSource>>{};
    for (final row in sources) {
      bySnapshot
          .putIfAbsent(row['snapshot_id']! as int, () => [])
          .add(
            JoinSource(
              entryPoint: row['entry_point']! as String,
              views: row['views']! as int,
              joins: row['joins']! as int,
              viewToJoinRate: row['view_to_join_rate'] as double?,
              shareOfJoins: row['share_of_joins'] as double?,
              campusViewToJoinRate: row['campus_view_to_join_rate'] as double?,
            ),
          );
    }
    return [
      for (final row in snapshots)
        JoinSnapshot(
          takenAt: DateTime.fromMillisecondsSinceEpoch(row['taken_at']! as int),
          sources: JoinSources(
            question: row['question']! as String,
            answer: row['answer']! as String,
            campusAnswer: row['campus_answer']! as String,
            days: row['days']! as int,
            views: row['views']! as int,
            joins: row['joins']! as int,
            sources: bySnapshot[row['id']! as int] ?? const [],
          ),
        ),
    ];
  }

  @override
  Future<void> add(String account, int groupId, JoinSnapshot snapshot) async {
    final owner = _account(account);
    final db = await _database();
    // One transaction: a snapshot is never left without its sources.
    await db.transaction((txn) async {
      final newest = await txn.query(
        'join_snapshots',
        columns: ['id', 'taken_at'],
        where: 'account = ? AND group_id = ?',
        whereArgs: [owner, groupId],
        orderBy: 'taken_at DESC',
        limit: 1,
      );
      if (newest.isNotEmpty) {
        final takenAt = DateTime.fromMillisecondsSinceEpoch(
          newest.single['taken_at']! as int,
        );
        if (snapshot.takenAt.difference(takenAt) <
            JoinHistoryStore.mergeWithin) {
          await txn.delete(
            'join_snapshots',
            where: 'id = ?',
            whereArgs: [newest.single['id']],
          );
        }
      }
      final answer = snapshot.sources;
      final id = await txn.insert('join_snapshots', {
        'account': owner,
        'group_id': groupId,
        'taken_at': snapshot.takenAt.millisecondsSinceEpoch,
        'days': answer.days,
        'views': answer.views,
        'joins': answer.joins,
        'question': answer.question,
        'answer': answer.answer,
        'campus_answer': answer.campusAnswer,
      });
      final batch = txn.batch();
      for (final (position, source) in answer.sources.indexed) {
        batch.insert('join_snapshot_sources', {
          'snapshot_id': id,
          'position': position,
          'entry_point': source.entryPoint,
          'views': source.views,
          'joins': source.joins,
          'view_to_join_rate': source.viewToJoinRate,
          'share_of_joins': source.shareOfJoins,
          'campus_view_to_join_rate': source.campusViewToJoinRate,
        });
      }
      await batch.commit(noResult: true);
      await txn.rawDelete(
        '''
        DELETE FROM join_snapshots
        WHERE account = ? AND group_id = ? AND id NOT IN (
          SELECT id FROM join_snapshots
          WHERE account = ? AND group_id = ?
          ORDER BY taken_at DESC LIMIT ?
        )''',
        [owner, groupId, owner, groupId, JoinHistoryStore.keep],
      );
    });
  }

  @override
  Future<void> clear(String account) async {
    final db = await _database();
    await db.delete(
      'join_snapshots',
      where: 'account = ?',
      whereArgs: [_account(account)],
    );
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}
