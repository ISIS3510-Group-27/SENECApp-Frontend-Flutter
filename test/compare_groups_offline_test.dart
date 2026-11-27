import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:senecapp/data/local/local_store.dart';
import 'package:senecapp/data/local/recommendation_snapshot_store.dart';
import 'package:senecapp/features/compare_groups/compare_groups_screen.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  late FakeBackend backend;
  late FakeConnectivity network;
  late _Documents store;

  setUp(() {
    backend = FakeBackend();
    network = FakeConnectivity();
    store = _Documents();
  });

  Future<void> start(WidgetTester tester) async {
    await pumpApp(
      tester,
      testServices(
        auth: signedInAuth(),
        backend: backend.client,
        connectivity: network,
        store: store,
      ),
    );
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    final button = find.text('Compare recommended groups');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> warm(WidgetTester tester) async {
    await start(tester);
    await open(tester);
    expect(store.saved, isNotNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  Future<void> choosePair(WidgetTester tester) async {
    for (final choice in [
      ('First organization', 'Viajeros Uniandes'),
      ('Second organization', 'Fotografía Uniandes'),
    ]) {
      final picker = find.byKey(ValueKey(choice.$1));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice.$2).last);
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'restores offline, retries locally and refreshes after reconnection',
    (tester) async {
      await warm(tester);
      backend.offline = true;
      network.set(connected: false);
      await tester.pumpAndSettle();
      final before = backend
          .requestsTo('GET', '/recommendations/groups')
          .length;
      await open(tester);
      expect(
        find.textContaining('Showing recommendations saved'),
        findsOneWidget,
      );
      expect(
        backend.requestsTo('GET', '/recommendations/groups'),
        hasLength(before),
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        backend.requestsTo('GET', '/recommendations/groups'),
        hasLength(before),
      );
      await choosePair(tester);
      final openGroup = find.byKey(const ValueKey('open-compared-group-3'));
      await tester.ensureVisible(openGroup);
      expect(tester.widget<TextButton>(openGroup).onPressed, isNull);
      expect(backend.requestsTo('GET', '/groups/3'), isEmpty);

      backend.offline = false;
      network.set(connected: true);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Showing recommendations saved'),
        findsNothing,
      );
      expect(
        backend.requestsTo('GET', '/recommendations/groups').length,
        greaterThan(before),
      );
      await tester.ensureVisible(openGroup);
      expect(tester.widget<TextButton>(openGroup).onPressed, isNotNull);
      await tester.tap(openGroup);
      await tester.pumpAndSettle();
      final view = backend.requestsTo('GET', '/groups/3').single;
      expect(view.url.queryParameters['entry_point'], 'recommendation');
      expect(
        view.url.queryParameters['rec_request_id'],
        FakeBackend.recRequestId,
      );
    },
  );

  testWidgets(
    'server failure with Wi-Fi uses saved recommendations without allowing details',
    (tester) async {
      await warm(tester);
      backend.recommenderDown = true;
      await open(tester);
      expect(find.byType(CompareGroupsScreen), findsOneWidget);
      expect(
        find.textContaining('Showing recommendations saved'),
        findsOneWidget,
      );
      expect(find.text("Couldn't load this"), findsNothing);
      await choosePair(tester);
      final openGroup = find.byKey(const ValueKey('open-compared-group-3'));
      await tester.ensureVisible(openGroup);
      expect(tester.widget<TextButton>(openGroup).onPressed, isNull);
    },
  );

  testWidgets(
    'offline first visit explains that a connection is needed when no snapshot exists',
    (tester) async {
      await start(tester);
      backend.offline = true;
      network.set(connected: false);
      await tester.pumpAndSettle();
      final before = backend
          .requestsTo('GET', '/recommendations/groups')
          .length;
      await open(tester);
      expect(find.text('Connect to load recommendations.'), findsOneWidget);
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(
        find.textContaining('Showing recommendations saved'),
        findsNothing,
      );
      expect(
        backend.requestsTo('GET', '/recommendations/groups'),
        hasLength(before),
      );
    },
  );
}

class _Documents extends NoLocalStore {
  Cached<Object?>? saved;
  @override
  Future<Cached<Object?>?> document(String key) async =>
      key == RecommendationSnapshotStore.key ? saved : null;

  @override
  Future<void> saveDocument(String key, Object? json) async {
    if (key == RecommendationSnapshotStore.key) {
      saved = Cached(json, DateTime.now());
    }
  }
}
