import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/local/sqlite_local_store.dart';
import 'package:senecapp/data/models/leader_insights.dart';
import 'package:senecapp/data/repositories/groups_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late SwitchableConnection connection;
  late AppServices services;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('senecapp_insights_');
    connection = SwitchableConnection(FakeBackend(adminOf: {1}).client);
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

  test('insights seen online are shown offline, marked as saved', () async {
    const length = Duration(hours: 2);
    final times = await services.groups.bestTimes(1, length: length);
    final audience = await services.groups.audience(1);
    final tips = await services.groups.profileTips(1);
    expect(services.offline.freshness.anyCached, isFalse);

    connection.online = false;

    final offlineTimes = await services.groups.bestTimes(1, length: length);
    expect(offlineTimes.slots.length, times.slots.length);
    expect((await services.groups.audience(1)).answer, audience.answer);
    expect((await services.groups.profileTips(1)).filled, tips.filled);
    final freshness = services.offline.freshness;
    expect(freshness.cachedAt(GroupsRepository.bestTimesKey(1)), isNotNull);
    expect(freshness.cachedAt(GroupsRepository.audienceKey(1)), isNotNull);
    expect(freshness.cachedAt(GroupsRepository.profileTipsKey(1)), isNotNull);
  });

  test('a length never loaded online is still an error offline', () async {
    await services.groups.bestTimes(1, length: const Duration(hours: 2));
    connection.online = false;

    await expectLater(
      services.groups.bestTimes(1, length: const Duration(hours: 1)),
      throwsA(isA<ApiException>()),
    );
  });

  test('a live answer clears the saved mark', () async {
    await services.groups.audience(1);
    connection.online = false;
    await services.groups.audience(1);
    expect(services.offline.freshness.anyCached, isTrue);

    connection.online = true;
    await services.groups.audience(1);
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
