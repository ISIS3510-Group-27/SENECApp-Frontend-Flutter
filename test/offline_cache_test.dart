import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/core/cache/lru_cache.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/local/sqlite_local_store.dart';
import 'package:senecapp/data/models/entry_point.dart';
import 'package:senecapp/data/models/group_filters.dart';
import 'package:senecapp/data/repositories/groups_repository.dart';
import 'package:senecapp/data/repositories/me_repository.dart';
import 'package:senecapp/state/session_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

/// Caching: the in-memory LRU in front of group and event pages, and the
/// network-first strategy that falls back to the phone's copy when the
/// backend can't be reached.
void main() {
  group('LruCache', () {
    test('drops the least recently used entry when full', () {
      final cache = LruCache<int, String>(capacity: 2)
        ..[1] = 'one'
        ..[2] = 'two';
      expect(cache[1], 'one'); // 1 is now the most recently used.
      cache[3] = 'three';

      expect(cache.keys, [1, 3]);
      expect(cache[2], isNull);
      expect(cache.length, 2);
    });

    test('rewriting an entry refreshes it without growing', () {
      final cache = LruCache<int, String>(capacity: 2)
        ..[1] = 'one'
        ..[2] = 'two'
        ..[1] = 'uno'
        ..[3] = 'three';

      expect(cache.keys, [1, 3]);
      expect(cache[1], 'uno');
    });

    test('counts hits and misses', () {
      final cache = LruCache<int, String>(capacity: 1)..[1] = 'one';
      cache[1];
      cache[2];

      expect((cache.hits, cache.misses), (1, 1));
    });
  });

  group('Offline copy', () {
    sqfliteFfiInit();

    late Directory directory;
    late SwitchableConnection connection;
    late AppServices services;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('senecapp_offline_');
      connection = SwitchableConnection(FakeBackend().client);
      services = testServices(
        auth: signedInAuth(),
        backend: connection,
        store: SqliteLocalStore(
          factory: databaseFactoryFfi,
          directory: directory.path,
        ),
      );
      await services.offline.store.open('s.arango@uniandes.edu.co');
    });

    tearDown(() async {
      await services.offline.store.wipe();
      await directory.delete(recursive: true);
    });

    test('what was seen online is shown offline, marked as saved', () async {
      final profile = await services.me.fetch();
      final mine = await services.groups.mine();
      final browse = await services.groups.search(const GroupFilters());
      final events = await services.events.list();
      final inbox = await services.notifications.list();
      final detail = await services.groups.detail(
        3,
        entryPoint: EntryPoint.explore,
      );
      expect(services.offline.freshness.anyCached, isFalse);

      connection.online = false;

      expect((await services.me.fetch()).name, profile.name);
      expect(
        [for (final g in await services.groups.mine()) g.id],
        [for (final g in mine) g.id],
      );
      final offlineBrowse = await services.groups.search(const GroupFilters());
      expect(offlineBrowse.total, browse.total);
      expect(offlineBrowse.items.length, browse.items.length);
      expect((await services.events.list()).length, events.length);
      expect((await services.notifications.list()).length, inbox.length);
      final offlineDetail = await services.groups.detail(
        3,
        entryPoint: EntryPoint.explore,
      );
      expect(offlineDetail.description, detail.description);

      final freshness = services.offline.freshness;
      expect(freshness.cachedAt(MeRepository.profileKey), isNotNull);
      expect(freshness.cachedAt(GroupsRepository.mineKey), isNotNull);
      expect(freshness.cachedAt(GroupsRepository.detailKey(3)), isNotNull);
    });

    test('a live answer clears the "saved" mark', () async {
      await services.groups.mine();
      connection.online = false;
      await services.groups.mine();
      expect(services.offline.freshness.anyCached, isTrue);

      connection.online = true;
      await services.groups.mine();
      expect(services.offline.freshness.anyCached, isFalse);
    });

    test('offline, something never seen is still an error', () async {
      connection.online = false;

      await expectLater(
        services.groups.mine(),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, '', true)),
      );
    });

    test('a search with words needs the connection', () async {
      await services.groups.search(const GroupFilters());
      connection.online = false;

      await expectLater(
        services.groups.search(const GroupFilters(query: 'tennis')),
        throwsA(isA<ApiException>()),
      );
    });

    test("a refusal isn't hidden behind the phone's copy", () async {
      final cache = services.offline;
      await cache.store.saveDocument('x', {'stale': true});

      await expectLater(
        cache.networkFirst<Object?>(
          'x',
          fetch: () async => throw const ApiException(403, 'Forbidden'),
          parse: (json) => json,
          save: (json) => cache.store.saveDocument('x', json),
          load: () => cache.store.document('x'),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, '', 403)),
      );
    });

    test('a group page opened this session is in memory', () async {
      expect(services.groups.recentDetail(3), isNull);
      await services.groups.detail(3, entryPoint: EntryPoint.explore);

      expect(services.groups.recentDetail(3)?.id, 3);
    });

    test('the app opens offline with the last profile, and sign-out deletes '
        'it', () async {
      SessionController session() => SessionController(
        auth: signedInAuth(),
        me: services.me,
        api: services.api,
        offline: services.offline,
      );

      final online = session();
      await online.start();
      expect(online.status, SessionStatus.signedIn);

      connection.online = false;
      final offline = session();
      await offline.start();
      expect(offline.status, SessionStatus.signedIn);
      expect(offline.student!.name, online.student!.name);

      await offline.signOut();
      await services.offline.store.open('s.arango@uniandes.edu.co');
      expect(await services.offline.store.document('me'), isNull);
    });
  });
}
