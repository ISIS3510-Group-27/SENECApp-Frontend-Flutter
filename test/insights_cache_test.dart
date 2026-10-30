import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:senecapp/app_services.dart';
import 'package:senecapp/core/cache/ttl_cache.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/local/sqlite_local_store.dart';
import 'package:senecapp/data/models/leader_insights.dart';
import 'package:senecapp/data/repositories/groups_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

class _Counting extends http.BaseClient {
  _Counting(this._inner);

  final http.Client _inner;
  final paths = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    paths.add(request.url.path);
    return _inner.send(request);
  }
}

void main() {
  sqfliteFfiInit();
  ttlCacheTests();

  late Directory directory;
  late SwitchableConnection connection;
  late AppServices services;
  late _Counting counting;
  late GroupsRepository groups;
  late DateTime now;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('senecapp_insights_');
    counting = _Counting(FakeBackend(adminOf: {1}).client);
    connection = SwitchableConnection(counting);
    now = DateTime(2026, 10, 30, 12);
    services = testServices(
      auth: signedInAuth(),
      backend: connection,
      store: SqliteLocalStore(
        factory: databaseFactoryFfi,
        directory: directory.path,
      ),
    );
    await services.offline.store.open('s.arango@uniandes.edu.co');
    groups = GroupsRepository(
      services.api,
      cache: services.offline,
      clock: () => now,
    );
  });

  tearDown(() async {
    await services.offline.store.wipe();
    await directory.delete(recursive: true);
  });

  test('insights seen online are shown offline, marked as saved', () async {
    const length = Duration(hours: 2);
    final times = await groups.bestTimes(1, length: length);
    final audience = await groups.audience(1);
    final tips = await groups.profileTips(1);
    expect(services.offline.freshness.anyCached, isFalse);

    connection.online = false;
    now = now.add(const Duration(minutes: 2));

    final offlineTimes = await groups.bestTimes(1, length: length);
    expect(offlineTimes.slots.length, times.slots.length);
    expect((await groups.audience(1)).answer, audience.answer);
    expect((await groups.profileTips(1)).filled, tips.filled);
    final freshness = services.offline.freshness;
    expect(freshness.cachedAt(GroupsRepository.bestTimesKey(1)), isNotNull);
    expect(freshness.cachedAt(GroupsRepository.audienceKey(1)), isNotNull);
    expect(freshness.cachedAt(GroupsRepository.profileTipsKey(1)), isNotNull);
  });

  test('a length never loaded online is still an error offline', () async {
    await groups.bestTimes(1, length: const Duration(hours: 2));
    connection.online = false;

    await expectLater(
      groups.bestTimes(1, length: const Duration(hours: 1)),
      throwsA(isA<ApiException>()),
    );
  });

  test('a live answer clears the saved mark', () async {
    await groups.audience(1);
    connection.online = false;
    now = now.add(const Duration(minutes: 2));
    await groups.audience(1);
    expect(services.offline.freshness.anyCached, isTrue);

    connection.online = true;
    await groups.audience(1);
    expect(services.offline.freshness.anyCached, isFalse);
  });

  test('a second open within the TTL does not reach the backend', () async {
    await groups.profileTips(1);
    await groups.profileTips(1);
    await groups.audience(1);
    await groups.audience(1);

    expect(counting.paths.where((p) => p.endsWith('/insights/profile')), hasLength(1));
    expect(counting.paths.where((p) => p.endsWith('/insights/audience')), hasLength(1));
  });

  test('after the TTL the backend is asked again', () async {
    await groups.profileTips(1);
    now = now.add(GroupsRepository.insightTtl);
    await groups.profileTips(1);

    expect(counting.paths.where((p) => p.endsWith('/insights/profile')), hasLength(2));
  });

  test('a saved copy is not kept in memory as if it were live', () async {
    await groups.audience(1);
    connection.online = false;
    now = now.add(const Duration(minutes: 2));
    await groups.audience(1);
    expect(services.offline.freshness.anyCached, isTrue);

    connection.online = true;
    await groups.audience(1);
    expect(services.offline.freshness.anyCached, isFalse);
  });

  test('a saved suggestion moves to its next occurrence', () {
    final slot = SuggestedSlot.fromJson({
      'weekday': 0,
      'start_time': '18:00',
      'end_time': '20:00',
      'free_members': 3,
      'free_ratio': 1.0,
      'attendance_rate': null,
      'next_starts_at': '2026-10-05T18:00:00Z',
    });

    final moved = slot.upcoming(DateTime.utc(2026, 10, 29, 12));

    expect(moved.nextStartsAt, DateTime.utc(2026, 11, 2, 18));
    expect(slot.upcoming(DateTime.utc(2026, 10, 1)), same(slot));
  });
}

void ttlCacheTests() {
  test('keeps at most its capacity and drops the least recently used', () {
    final cache = TtlCache<String, int>(
      capacity: 2,
      ttl: const Duration(minutes: 1),
    );
    cache['a'] = 1;
    cache['b'] = 2;
    expect(cache['a'], 1);
    cache['c'] = 3;

    expect(cache['b'], isNull);
    expect(cache['a'], 1);
    expect(cache['c'], 3);
    expect(cache.length, 2);
  });

  test('forgets an entry once its time to live has passed', () {
    var now = DateTime(2026, 10, 30);
    final cache = TtlCache<String, int>(
      capacity: 5,
      ttl: const Duration(seconds: 60),
      clock: () => now,
    );
    cache['a'] = 1;

    now = now.add(const Duration(seconds: 59));
    expect(cache['a'], 1);
    now = now.add(const Duration(seconds: 61));
    expect(cache['a'], isNull);
    expect(cache.hits, 1);
    expect(cache.expired, 1);
    expect(cache.length, 0);
  });

  test('counts misses and removes entries on request', () {
    final cache = TtlCache<String, int>(
      capacity: 5,
      ttl: const Duration(seconds: 60),
    );
    expect(cache['x'], isNull);
    cache['x'] = 1;
    expect(cache.remove('x'), 1);
    expect(cache['x'], isNull);
    expect(cache.misses, 2);
  });
}
