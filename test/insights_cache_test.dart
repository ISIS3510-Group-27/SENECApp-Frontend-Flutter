import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:senecapp/app_services.dart';
import 'package:senecapp/core/cache/ttl_cache.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/local/insight_store.dart';
import 'package:senecapp/data/models/leader_insights.dart';
import 'package:senecapp/data/repositories/insights_repository.dart';

import 'support/fakes.dart';

class _Counting extends http.BaseClient {
  _Counting(this._inner);

  final http.Client _inner;
  final paths = <String>[];

  int count(String suffix) => paths.where((p) => p.endsWith(suffix)).length;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    paths.add(request.url.path);
    return _inner.send(request);
  }
}

void main() {
  ttlCacheTests();
  fileStoreTests();

  const account = 's.arango@uniandes.edu.co';
  late Directory directory;
  late SwitchableConnection connection;
  late AppServices services;
  late _Counting counting;
  late InsightStore store;
  late InsightsRepository insights;
  late DateTime now;

  InsightsRepository build() => InsightsRepository(
    api: services.api,
    store: store,
    clock: () => now,
  )..useAccount(account);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('senecapp_insights_');
    counting = _Counting(FakeBackend(adminOf: {1}).client);
    connection = SwitchableConnection(counting);
    now = DateTime(2026, 10, 30, 12);
    services = testServices(auth: signedInAuth(), backend: connection);
    store = FileInsightStore(directory: () async => directory);
    insights = build();
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('a repeated request is answered from memory', () async {
    await insights.profileTips(1);
    await insights.profileTips(1);
    await insights.audience(1);
    await insights.audience(1);

    expect(counting.count('/insights/profile'), 1);
    expect(counting.count('/insights/audience'), 1);
  });

  test('a fresh stored copy skips the network after a restart', () async {
    final first = await insights.profileTips(1);
    final restarted = build();
    now = now.add(const Duration(minutes: 5));

    final again = await restarted.profileTips(1);

    expect(again.filled, first.filled);
    expect(counting.count('/insights/profile'), 1);
  });

  test('a stored copy older than the fresh window is fetched again', () async {
    await insights.profileTips(1);
    final restarted = build();
    now = now.add(InsightsRepository.diskFreshFor);

    await restarted.profileTips(1);

    expect(counting.count('/insights/profile'), 2);
    expect((await store.read(account, InsightKeys.profileTips(1)))!.savedAt, now);
  });

  test('memory expires after its time to live', () async {
    await insights.audience(1);
    now = now.add(InsightsRepository.memoryTtl);
    await insights.audience(1);

    expect(counting.count('/insights/audience'), 1);
  });

  test('force skips both layers', () async {
    await insights.audience(1);
    await insights.audience(1, force: true);

    expect(counting.count('/insights/audience'), 2);
  });

  test('offline falls back to the stored copy and marks it', () async {
    const length = Duration(hours: 2);
    final times = await insights.bestTimes(1, length: length);
    final audience = await insights.audience(1);
    final tips = await insights.profileTips(1);
    final restarted = build();
    connection.online = false;
    now = now.add(const Duration(hours: 3));

    expect(
      (await restarted.bestTimes(1, length: length)).slots.length,
      times.slots.length,
    );
    expect((await restarted.audience(1)).answer, audience.answer);
    expect((await restarted.profileTips(1)).filled, tips.filled);
    expect(restarted.copySavedAt(InsightKeys.audience(1)), isNotNull);
    expect(restarted.copySavedAt(InsightKeys.profileTips(1)), isNotNull);
    expect(restarted.copySavedAt(InsightKeys.bestTimes(1, length)), isNotNull);
  });

  test('a length never loaded online is still an error offline', () async {
    await insights.bestTimes(1, length: const Duration(hours: 2));
    connection.online = false;

    await expectLater(
      insights.bestTimes(1, length: const Duration(hours: 1)),
      throwsA(isA<ApiException>()),
    );
  });

  test('a live answer clears the saved mark', () async {
    await insights.audience(1);
    final restarted = build();
    connection.online = false;
    now = now.add(const Duration(hours: 1));
    await restarted.audience(1);
    expect(restarted.copySavedAt(InsightKeys.audience(1)), isNotNull);

    connection.online = true;
    await restarted.audience(1);
    expect(restarted.copySavedAt(InsightKeys.audience(1)), isNull);
  });

  test('a copy older than the keep window is dropped', () async {
    await insights.audience(1);
    final restarted = build();
    connection.online = false;
    now = now.add(InsightsRepository.keepFor + const Duration(minutes: 1));

    await expectLater(restarted.audience(1), throwsA(isA<ApiException>()));
    expect(await store.read(account, InsightKeys.audience(1)), isNull);
  });

  test('forget removes memory and disk', () async {
    await insights.profileTips(1);
    await insights.forget(InsightKeys.profileTips(1));
    await insights.profileTips(1);

    expect(counting.count('/insights/profile'), 2);
  });

  test('another account never sees the stored copy', () async {
    await insights.audience(1);
    final other = build()..useAccount('someone.else@uniandes.edu.co');
    connection.online = false;

    await expectLater(other.audience(1), throwsA(isA<ApiException>()));
  });

  test('without an account nothing is written to disk', () async {
    final anonymous = InsightsRepository(
      api: services.api,
      store: store,
      clock: () => now,
    );
    await anonymous.audience(1);

    expect(await store.read(account, InsightKeys.audience(1)), isNull);
    expect(directory.listSync(recursive: true).whereType<File>(), isEmpty);
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

void fileStoreTests() {
  late Directory directory;
  late FileInsightStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('senecapp_store_');
    store = FileInsightStore(directory: () async => directory);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('writes and reads a body with its date', () async {
    final at = DateTime(2026, 10, 30, 9);
    await store.write('A@x.co', 'k', {'n': 1}, at);

    final read = await store.read('a@x.co', 'k');

    expect((read!.body as Map)['n'], 1);
    expect(read.savedAt, at);
  });

  test('a corrupt file is discarded', () async {
    await store.write('a@x.co', 'k', {'n': 1}, DateTime(2026));
    final file = directory
        .listSync(recursive: true)
        .whereType<File>()
        .single;
    await file.writeAsString('{not json');

    expect(await store.read('a@x.co', 'k'), isNull);
    expect(file.existsSync(), isFalse);
  });

  test('overwrites and removes', () async {
    await store.write('a@x.co', 'k', 1, DateTime(2026));
    await store.write('a@x.co', 'k', 2, DateTime(2027));
    expect((await store.read('a@x.co', 'k'))!.body, 2);

    await store.remove('a@x.co', 'k');
    expect(await store.read('a@x.co', 'k'), isNull);
  });

  test('accounts do not share files', () async {
    await store.write('a@x.co', 'k', 1, DateTime(2026));

    expect(await store.read('b@x.co', 'k'), isNull);
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
