import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/core/theme/app_colors.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/local/health_store.dart';
import 'package:senecapp/data/models/group_health.dart';
import 'package:senecapp/data/models/rso.dart';
import 'package:senecapp/data/models/rso_category.dart';
import 'package:senecapp/data/repositories/group_health_repository.dart';
import 'package:senecapp/features/group_health/group_health_screen.dart';

import 'support/fakes.dart';

class _Counting extends http.BaseClient {
  _Counting(this._inner);

  final http.Client _inner;
  int health = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path.endsWith('/insights/health')) health++;
    return _inner.send(request);
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const account = 's.arango@uniandes.edu.co';

  group('HealthTrend', () {
    test('averages the last three weeks and finds the peak', () {
      final trend = HealthTrend.of([6, 6, 9, 3]);

      expect(trend.average, [6, 6, 7, 6]);
      expect(trend.peak, 9);
      expect(trend.lastChange, closeTo(-0.667, 0.001));
    });

    test('has no change when the week before had nobody', () {
      expect(HealthTrend.of([0, 4]).lastChange, isNull);
      expect(HealthTrend.of([]).peak, 0);
    });
  });

  group('HiveHealthStore', () {
    late Directory directory;
    late HiveHealthStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('senecapp_hive_');
      Hive.init(directory.path);
      store = HiveHealthStore(open: () => Hive.openBox<String>('health_test'));
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await directory.delete(recursive: true);
    });

    test('keeps one copy per account and group', () async {
      final at = DateTime(2026, 11, 25, 9);
      await store.write('A@x.co', 1, {'n': 1}, at);
      await store.write('a@x.co', 1, {'n': 2}, at);

      final read = await store.read('a@x.co', 1);

      expect(read!.body['n'], 2);
      expect(read.savedAt, at);
      expect(await store.read('b@x.co', 1), isNull);
      expect(await store.read('a@x.co', 2), isNull);
    });

    test('removes a copy', () async {
      await store.write('a@x.co', 1, {'n': 1}, DateTime(2026));
      await store.remove('a@x.co', 1);

      expect(await store.read('a@x.co', 1), isNull);
    });
  });

  group('GroupHealthRepository', () {
    late SwitchableConnection connection;
    late _Counting counting;
    late MemoryHealthStore store;
    late DateTime now;
    late AppServices services;

    GroupHealthRepository build() => GroupHealthRepository(
      api: services.api,
      store: store,
      clock: () => now,
    )..useAccount(account);

    setUp(() {
      counting = _Counting(FakeBackend(adminOf: {1}).client);
      connection = SwitchableConnection(counting);
      store = MemoryHealthStore();
      now = DateTime(2026, 11, 25, 12);
      services = testServices(auth: signedInAuth(), backend: connection);
    });

    test('answers a second open from memory', () async {
      final health = build();
      await health.load(1);
      await health.load(1);

      expect(counting.health, 1);
    });

    test('a fresh stored copy skips the network after a restart', () async {
      await build().load(1);
      now = now.add(const Duration(minutes: 10));

      final result = await build().load(1);

      expect(counting.health, 1);
      expect(result.fromCopy, isTrue);
      expect(result.health.declining, isTrue);
    });

    test('an older copy is refreshed from the network', () async {
      await build().load(1);
      now = now.add(GroupHealthRepository.diskFreshFor);

      final result = await build().load(1);

      expect(counting.health, 2);
      expect(result.fromCopy, isFalse);
    });

    test('offline it falls back to the stored copy', () async {
      await build().load(1);
      connection.online = false;
      now = now.add(const Duration(days: 3));

      final result = await build().load(1);

      expect(result.fromCopy, isTrue);
      expect(result.health.attendance, [6, 6, 7, 6, 3, 2, 2, 1]);
    });

    test('a copy older than the keep window is not shown', () async {
      await build().load(1);
      connection.online = false;
      now = now.add(GroupHealthRepository.keepFor + const Duration(hours: 1));

      await expectLater(build().load(1), throwsA(isA<ApiException>()));
      expect(await store.read(account, 1), isNull);
    });

    test('a refusal is never hidden behind a copy', () async {
      await expectLater(build().load(2), throwsA(isA<ApiException>()));
    });

    test('force goes to the network', () async {
      final health = build();
      await health.load(1);
      await health.load(1, force: true);

      expect(counting.health, 2);
    });
  });

  group('GroupHealthScreen', () {
    setUp(() {
      GroupHealthScreen.computeTrend = (weeks) async => HealthTrend.of(weeks);
    });

    const tennis = Rso(
      id: 1,
      name: 'Tennis Uniandes',
      category: RsoCategory.sports,
      members: 142,
      description: 'Competitive and recreational tennis for all levels.',
      tags: ['Tennis'],
      color: AppColors.primary,
      verified: true,
      myRole: 'admin',
    );

    Future<void> open(WidgetTester tester, AppServices services) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Provider<AppServices>.value(
          value: services,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push(GroupHealthScreen.route(tennis)),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the decline, the chart and what brings members back', (
      tester,
    ) async {
      final services = testServices(
        auth: signedInAuth(),
        backend: FakeBackend(adminOf: {1}).client,
      );
      services.health.useAccount(account);

      await open(tester, services);

      expect(find.text('Attendance is dropping'), findsOneWidget);
      expect(find.text('Event reminders running'), findsOneWidget);
      expect(find.text('50%'), findsWidgets);
      expect(find.text('25%'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('offline with a saved copy it says how old it is', (
      tester,
    ) async {
      final connection = SwitchableConnection(
        FakeBackend(adminOf: {1}).client,
      );
      final store = MemoryHealthStore();
      final services = testServices(
        auth: signedInAuth(),
        backend: connection,
        healthStore: store,
      );
      final warmUp = GroupHealthRepository(api: services.api, store: store)
        ..useAccount(account);
      await tester.runAsync(() => warmUp.load(1));
      connection.online = false;
      services.health.useAccount(account);

      await open(tester, services);

      expect(find.textContaining('Saved'), findsOneWidget);
      expect(find.text('Attendance is dropping'), findsOneWidget);
    });
  });
}
