import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/core/theme/app_colors.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/local/join_history_store.dart';
import 'package:senecapp/data/models/join_sources.dart';
import 'package:senecapp/data/models/rso.dart';
import 'package:senecapp/data/models/rso_category.dart';
import 'package:senecapp/data/repositories/join_sources_repository.dart';
import 'package:senecapp/features/join_sources/join_sources_screen.dart';
import 'package:senecapp/state/connection_status.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

const _account = 's.arango@uniandes.edu.co';

JoinSources _answer(int joins) => JoinSources(
  question: 'Which entry point produces more joins?',
  answer: 'Most of your joins come from recommendations.',
  campusAnswer: 'Recommendation produces more joins.',
  days: 90,
  views: 40,
  joins: joins,
  sources: [
    JoinSource(
      entryPoint: 'recommendation',
      views: 20,
      joins: joins - 1,
      viewToJoinRate: (joins - 1) / 20,
      shareOfJoins: (joins - 1) / joins,
      campusViewToJoinRate: 0.12,
    ),
    const JoinSource(entryPoint: 'search', views: 20, joins: 1),
  ],
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  storeTests();
  repositoryTests();
  screenTests();
}

void storeTests() {
  Future<void> exercise(JoinHistoryStore store) async {
    final start = DateTime(2026, 11, 20, 9);
    await store.add(
      _account,
      1,
      JoinSnapshot(takenAt: start, sources: _answer(4)),
    );
    // Within 6 hours: replaces the newest instead of piling up.
    await store.add(
      _account,
      1,
      JoinSnapshot(
        takenAt: start.add(const Duration(hours: 2)),
        sources: _answer(5),
      ),
    );
    var recent = await store.recent(_account, 1);
    expect(recent, hasLength(1));
    expect(recent.single.sources.joins, 5);
    expect(recent.single.sources.sources.map((s) => s.entryPoint), [
      'recommendation',
      'search',
    ]);

    for (var day = 1; day <= 14; day++) {
      await store.add(
        _account,
        1,
        JoinSnapshot(
          takenAt: start.add(Duration(days: day)),
          sources: _answer(5 + day),
        ),
      );
    }
    recent = await store.recent(_account, 1);
    expect(recent, hasLength(JoinHistoryStore.keep));
    expect(recent.first.sources.joins, 19, reason: 'newest first');
    expect(recent.first.sources.sources.first.campusViewToJoinRate, 0.12);

    expect(await store.recent('other@uniandes.edu.co', 1), isEmpty);
    expect(await store.recent(_account, 2), isEmpty);
    await store.clear(_account.toUpperCase());
    expect(await store.recent(_account, 1), isEmpty);
  }

  group('join history store', () {
    test('memory store merges close snapshots and keeps 12', () async {
      await exercise(MemoryJoinHistoryStore());
    });

    test('sqlite store does the same on two related tables', () async {
      final directory = await Directory.systemTemp.createTemp('senecapp_join_');
      final store = SqliteJoinHistoryStore(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}/join_history.db',
      );
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      await exercise(store);
    });

    test('sqlite history survives closing the app', () async {
      final directory = await Directory.systemTemp.createTemp('senecapp_join_');
      final location = '${directory.path}/join_history.db';
      final first = SqliteJoinHistoryStore(
        factory: databaseFactoryFfi,
        databasePath: location,
      );
      await first.add(
        _account,
        3,
        JoinSnapshot(takenAt: DateTime(2026, 11, 1), sources: _answer(7)),
      );
      await first.close();
      final second = SqliteJoinHistoryStore(
        factory: databaseFactoryFfi,
        databasePath: location,
      );
      addTearDown(() async {
        await second.close();
        await directory.delete(recursive: true);
      });

      final recent = await second.recent(_account, 3);
      expect(recent.single.sources.joins, 7);
      expect(recent.single.sources.sources, hasLength(2));
    });
  });
}

void repositoryTests() {
  group('join sources repository (stale-while-revalidate)', () {
    late FakeBackend backend;
    late SwitchableConnection connection;
    late MemoryJoinHistoryStore store;
    late DateTime now;
    late JoinSourcesRepository repository;

    setUp(() {
      backend = FakeBackend(adminOf: {1});
      connection = SwitchableConnection(backend.client);
      store = MemoryJoinHistoryStore();
      now = DateTime(2026, 11, 20, 9);
      final services = testServices(auth: signedInAuth(), backend: connection);
      repository = JoinSourcesRepository(
        api: services.api,
        store: store,
        clock: () => now,
      )..useAccount(_account);
    });

    test('first visit: one fresh answer, saved on the phone', () async {
      final answers = await repository.watch(1).toList();

      expect(answers, hasLength(1));
      expect(answers.single.fromPhone, isFalse);
      expect(answers.single.current.joins, 8);
      expect((await store.recent(_account, 1)).single.sources.joins, 8);
    });

    test(
      'reopening within 2 minutes answers from memory, no request',
      () async {
        await repository.watch(1).toList();
        now = now.add(const Duration(minutes: 1));

        final answers = await repository.watch(1).toList();

        expect(answers.single.current.joins, 8);
        expect(backend.joinSourcesServed, 1);
      },
    );

    test('later: the saved copy first, then the fresh answer', () async {
      await repository.watch(1).toList();
      now = now.add(const Duration(days: 1));
      backend.joinSourcesExtra = 3;

      final answers = await repository.watch(1).toList();

      expect(answers, hasLength(2));
      expect(answers.first.fromPhone, isTrue);
      expect(answers.first.refreshing, isTrue);
      expect(answers.first.current.joins, 8);
      expect(answers.last.fromPhone, isFalse);
      expect(answers.last.current.joins, 11);
      // Compared with yesterday's visit: three more from recommendations.
      expect(answers.last.newJoins('recommendation'), 3);
      expect(answers.last.newJoins('search'), 0);
    });

    test('offline: the saved copy stays, marked as not refreshing', () async {
      await repository.watch(1).toList();
      now = now.add(const Duration(hours: 1));
      connection.online = false;

      final answers = await repository.watch(1).toList();

      expect(answers, hasLength(2));
      expect(answers.last.fromPhone, isTrue);
      expect(answers.last.refreshing, isFalse);
      expect(answers.last.current.joins, 8);
    });

    test('offline with nothing saved: the error reaches the screen', () async {
      connection.online = false;

      await expectLater(
        repository.watch(1).toList(),
        throwsA(isA<ApiException>()),
      );
    });

    test("one leader never sees another's saved answers", () async {
      await repository.watch(1).toList();
      repository.useAccount('other.leader@uniandes.edu.co');
      connection.online = false;

      await expectLater(
        repository.watch(1).toList(),
        throwsA(isA<ApiException>()),
      );
    });
  });
}

void screenTests() {
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

  Future<(FakeBackend, FakeConnectivity, SwitchableConnection)> open(
    WidgetTester tester, {
    bool online = true,
  }) async {
    final backend = FakeBackend(adminOf: {1});
    final connection = SwitchableConnection(backend.client)..online = online;
    final connectivity = FakeConnectivity()..connected = online;
    final services = testServices(
      auth: signedInAuth(),
      backend: connection,
      connectivity: connectivity,
    );
    services.joinSources.useAccount(_account);
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppServices>.value(value: services),
          ChangeNotifierProvider(
            create: (_) => ConnectionStatus(connectivity)..start(),
          ),
        ],
        child: const MaterialApp(home: JoinSourcesScreen(rso: tennis)),
      ),
    );
    await tester.pumpAndSettle();
    return (backend, connectivity, connection);
  }

  group('join sources screen', () {
    testWidgets('shows joins per entry point with the campus rate', (
      tester,
    ) async {
      final (backend, _, _) = await open(tester);

      expect(find.text('Where your members come from'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('Recommended for you'), findsOneWidget);
      expect(find.text('Search and filters'), findsOneWidget);
      expect(find.textContaining('campus 12%'), findsOneWidget);
      expect(
        backend.requestsTo('GET', '/groups/1/insights/join-sources'),
        hasLength(1),
      );
    });

    testWidgets('offline first visit says why it needs a connection', (
      tester,
    ) async {
      await open(tester, online: false);

      expect(
        find.textContaining('the first look needs a connection'),
        findsOneWidget,
      );
    });

    testWidgets('loads by itself when the connection returns', (tester) async {
      final (_, connectivity, connection) = await open(tester, online: false);

      connection.online = true;
      connectivity.set(connected: true);
      await tester.pumpAndSettle();

      expect(find.text('Recommended for you'), findsOneWidget);
    });
  });
}
