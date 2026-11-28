import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:senecapp/app.dart';
import 'package:senecapp/core/assets/asset_catalog.dart';
import 'package:senecapp/data/connectivity/connectivity_service.dart';
import 'package:senecapp/data/local/recommendation_snapshot_store.dart';
import 'package:senecapp/data/local/sqlite_local_store.dart';

import '../test/support/fakes.dart';

/// Android session with the real SQLite/plugin/UI and a controlled backend.
/// No Firebase account is needed and no production memberships are modified.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('comparison online, native offline restore and reconnection', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await AssetCatalog.load();
    final network = PlusConnectivityService();
    final backend = FakeBackend();
    final client = MockClient((request) async {
      if (!await network.isConnected()) {
        throw http.ClientException('Diagnostic network offline');
      }
      final forwarded = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes;
      return backend.client.send(forwarded).then(http.Response.fromStream);
    });
    final database = SqliteLocalStore();
    final services = testServices(
      auth: signedInAuth(),
      backend: client,
      connectivity: network,
      store: database,
    );
    await tester.pumpWidget(SenecApp(services: services));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    Future<void> openComparison() async {
      final entry = find.text('Compare recommended groups');
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
    }

    Future<void> choosePair() async {
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

    Future<void> waitForNetwork(bool connected) async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (DateTime.now().isBefore(deadline)) {
        if (await network.isConnected() == connected) {
          await tester.pumpAndSettle();
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
      }
      fail('The host did not switch network connectivity to $connected');
    }

    await openComparison();
    await choosePair();
    expect(
      (await RecommendationSnapshotStore(
        store: database,
      ).read())!.value.requestId,
      isEmpty,
    );
    debugPrint('SPRINT4_ONLINE_READY');
    await waitForNetwork(false);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openComparison();
    expect(
      find.textContaining('Showing recommendations saved'),
      findsOneWidget,
    );
    await choosePair();
    final open = find.byKey(const ValueKey('open-compared-group-3'));
    await tester.ensureVisible(open);
    expect(tester.widget<TextButton>(open).onPressed, isNull);
    debugPrint('SPRINT4_OFFLINE_READY');
    await waitForNetwork(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Showing recommendations saved'), findsNothing);
    await tester.ensureVisible(open);
    expect(tester.widget<TextButton>(open).onPressed, isNotNull);
    debugPrint('SPRINT4_RECONNECTED_READY');
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.tap(open);
    await tester.pumpAndSettle();
    // This CTA is pinned, so scrolling to it can move its ancestor viewport.
    await tester.tap(find.text('Join RSO').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    final view = backend.requestsTo('GET', '/groups/3').single;
    final join = backend.requestsTo('POST', '/groups/3/join').single;
    expect(view.url.queryParameters['entry_point'], 'recommendation');
    expect(
      view.url.queryParameters['rec_request_id'],
      FakeBackend.recRequestId,
    );
    expect(join.body, contains('recommendation'));
    expect(join.body, contains(FakeBackend.recRequestId));
    binding.reportData = {
      'completed': true,
      'backend': 'in-memory controlled fixture; no production writes',
      'platform': Platform.operatingSystem,
      'sqlite_snapshot': true,
      'offline_details_disabled': true,
      'reconnected_details_enabled': true,
      'recommendation_view': view.url.queryParameters,
      'recommendation_join_verified': true,
    };
  }, timeout: const Timeout(Duration(minutes: 8)));
}
