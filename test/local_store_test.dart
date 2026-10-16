import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/data/local/sqlite_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The offline copy on a real SQLite database (through FFI on the computer
/// running the tests, the same engine phones use).
void main() {
  sqfliteFfiInit();

  late Directory directory;
  var now = DateTime(2026, 10, 16, 10, 42);

  SqliteLocalStore store() => SqliteLocalStore(
    factory: databaseFactoryFfi,
    directory: directory.path,
    clock: () => now,
  );

  Map<String, dynamic> group(int id, [String? name]) => {
    'id': id,
    'name': name ?? 'Group $id',
  };

  Map<String, dynamic> event(int id, {int groupId = 1}) => {
    'id': id,
    'group_id': groupId,
    'starts_at': '2026-10-20T15:00:00Z',
    'title': 'Event $id',
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('senecapp_store_');
    now = DateTime(2026, 10, 16, 10, 42);
  });

  tearDown(() => directory.delete(recursive: true));

  test('lists keep their order and share the group rows', () async {
    final s = store();
    await s.open('s.arango@uniandes.edu.co');

    await s.saveGroups('mine', [group(2), group(1)]);
    await s.saveGroups('browse', [group(1, 'Renamed'), group(3)]);

    final mine = await s.groups('mine');
    expect(mine!.value, [group(2), group(1, 'Renamed')]);
    expect(mine.savedAt, now);
    expect((await s.groups('browse'))!.value, [group(1, 'Renamed'), group(3)]);
    await s.wipe();
  });

  test('a list never stored is null, one stored empty is empty', () async {
    final s = store();
    await s.open('a@uniandes.edu.co');

    expect(await s.groups('mine'), isNull);
    await s.saveGroups('mine', []);
    expect((await s.groups('mine'))!.value, isEmpty);
    await s.wipe();
  });

  test('details, events, the inbox and documents round-trip', () async {
    final s = store();
    await s.open('a@uniandes.edu.co');

    await s.saveGroupDetail({...group(5), 'about': 'Long text'});
    await s.saveEvents('all', [event(1), event(2, groupId: 5)]);
    await s.saveEventDetail({...event(2, groupId: 5), 'description': 'More'});
    await s.saveNotifications([
      {'id': 9, 'title': 'Newest'},
      {'id': 4, 'title': 'Older'},
    ]);
    await s.saveDocument('me', {'id': 1, 'interests': <String>[]});

    expect((await s.groupDetail(5))!.value['about'], 'Long text');
    expect(await s.groupDetail(6), isNull);
    expect((await s.events('all'))!.value, [event(1), event(2, groupId: 5)]);
    expect((await s.eventDetail(2))!.value['description'], 'More');
    expect(
      [for (final n in (await s.notifications())!.value) (n! as Map)['id']],
      [9, 4],
    );
    expect((await s.document('me'))!.value, {'id': 1, 'interests': []});
    await s.wipe();
  });

  test('each account has its own copy, deleted at sign-out', () async {
    final s = store();
    await s.open('first@uniandes.edu.co');
    await s.saveDocument('me', {'id': 1});

    await s.open('second@uniandes.edu.co');
    expect(await s.document('me'), isNull);
    await s.wipe();

    await s.open('first@uniandes.edu.co');
    expect((await s.document('me'))!.value, {'id': 1});
    await s.wipe();

    await s.open('first@uniandes.edu.co');
    expect(await s.document('me'), isNull);
    await s.wipe();
  });

  test('nothing is stored or read before an account is open', () async {
    final s = store();
    await s.saveDocument('me', {'id': 1});
    expect(await s.document('me'), isNull);
  });

  test('old rows no list points to are pruned when reopened', () async {
    final s = store();
    await s.open('a@uniandes.edu.co');
    await s.saveGroups('mine', [group(1)]);
    await s.saveGroupDetail(group(2)); // Opened once, in no list.

    now = now.add(SqliteLocalStore.keepUnlisted + const Duration(days: 1));
    await s.open('a@uniandes.edu.co');

    expect(await s.groupDetail(2), isNull);
    expect((await s.groups('mine'))!.value, [group(1)]);
    await s.wipe();
  });
}
