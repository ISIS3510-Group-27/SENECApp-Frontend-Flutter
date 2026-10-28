import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:senecapp/core/widgets/rso_list_tile.dart';
import 'package:senecapp/data/connectivity/connectivity_service.dart';
import 'package:senecapp/features/check_in/check_in_view_model.dart';
import 'package:senecapp/features/discover/discover_screen.dart';
import 'package:senecapp/state/connection_status.dart';

import 'support/fakes.dart';

/// Eventual connectivity: what each screen does when the connection goes, and
/// what happens when it comes back.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('ConnectionStatus', () {
    test('reports going offline and announces each return', () async {
      final network = FakeConnectivity();
      final status = ConnectionStatus(network)..start();
      final returns = <void>[];
      status.reconnected.listen(returns.add);

      network.set(connected: false);
      await Future<void>.delayed(Duration.zero);
      expect(status.online, isFalse);
      expect(status.offlineSince, isNotNull);

      network
        ..set(connected: true)
        ..set(connected: true); // A repeated "online" is not a return.
      await Future<void>.delayed(Duration.zero);
      expect(status.online, isTrue);
      expect(returns, hasLength(1));
      status.dispose();
    });

    test('starts from the real state of the network', () async {
      final network = FakeConnectivity()..connected = false;
      final status = ConnectionStatus(network)..start();
      await Future<void>.delayed(Duration.zero);

      expect(status.online, isFalse);
      status.dispose();
    });
  });

  group('Screens', () {
    late Offline offline;

    Future<void> openApp(WidgetTester tester) async {
      offline = Offline(FakeBackend());
      await pumpApp(
        tester,
        testServices(
          auth: signedInAuth(),
          backend: offline.connection,
          connectivity: offline.network,
        ),
      );
    }

    testWidgets('the banner says so, and coming back refreshes the app', (
      tester,
    ) async {
      await openApp(tester);
      expect(find.textContaining("You're offline"), findsNothing);

      offline.cut();
      await tester.pumpAndSettle();
      expect(
        find.text("You're offline. You can still browse what you saw last."),
        findsOneWidget,
      );

      final before = offline.backend.requestsTo('GET', '/me/groups').length;
      offline.restore();
      await tester.pumpAndSettle();
      expect(find.textContaining("You're offline"), findsNothing);
      expect(
        find.text('Back online. Updating your groups and events.'),
        findsOneWidget,
      );
      expect(
        offline.backend.requestsTo('GET', '/me/groups').length,
        greaterThan(before),
      );
    });

    testWidgets('Discover: searching offline says so and sends nothing', (
      tester,
    ) async {
      await openApp(tester);
      offline.cut();
      await tester.pumpAndSettle();
      final searches = offline.backend.requestsTo('GET', '/groups').length;

      await tester.enterText(find.byType(TextField).first, 'tennis');
      await tester.pump(DiscoverScreen.searchDebounce);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Search and filters need a connection'),
        findsOneWidget,
      );
      expect(offline.backend.requestsTo('GET', '/groups'), hasLength(searches));
      // The groups already on screen stay there.
      expect(find.byType(RsoListTile), findsWidgets);
    });

    testWidgets('a group page: joining offline is stopped with a reason', (
      tester,
    ) async {
      await openApp(tester);
      await tester.tap(find.widgetWithText(RsoListTile, 'Viajeros Uniandes'));
      await tester.pumpAndSettle();

      offline.cut();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join RSO'));
      await tester.pumpAndSettle();

      expect(find.text('Joining needs a connection'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // The join form never opened, and nothing was sent.
      expect(find.text('Join'), findsNothing);
      expect(offline.backend.requestsTo('POST', '/groups/3/join'), isEmpty);
    });

    testWidgets('Events: Free right now explains why it needs a connection', (
      tester,
    ) async {
      await openApp(tester);
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();

      offline.cut();
      await tester.pumpAndSettle();
      expect(
        find.text('Needs a connection to see where you are now'),
        findsOneWidget,
      );

      await tester.tap(find.text('Free right now?'));
      await tester.pumpAndSettle();
      expect(find.text('Free right now needs a connection'), findsOneWidget);
      expect(
        offline.backend.requestsTo('GET', '/recommendations/events/free-now'),
        isEmpty,
      );
    });
  });

  group('Check-in offline', () {
    const live = 2;

    test('the scan is kept, with its position, and sent once back', () async {
      final offline = Offline(FakeBackend(liveEventId: live));
      final services = testServices(
        auth: signedInAuth(),
        backend: offline.connection,
        connectivity: offline.network,
      );
      final status = ConnectionStatus(offline.network)..start();
      var checkedIn = 0;
      final location = FakeLocationService();
      final vm = CheckInViewModel(
        events: services.events,
        location: location,
        locationOptIn: () => true,
        onCheckedIn: () => checkedIn++,
        analytics: services.analytics,
        isOnline: () => status.online,
        reconnected: status.reconnected,
      );

      offline.cut();
      await Future<void>.delayed(Duration.zero);
      await vm.submit(live, FakeBackend.checkInCode(live));

      expect(vm.waitingForConnection, isTrue);
      expect(vm.scanning, isFalse);
      expect(location.reads, 1); // Read at the venue, not later.
      expect(
        offline.backend.requestsTo('POST', '/events/$live/check-in'),
        isEmpty,
      );

      offline.restore();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(vm.waitingForConnection, isFalse);
      expect(vm.result, isNotNull);
      expect(checkedIn, 1);
      expect(location.reads, 1);
      expect(
        offline.backend.requestsTo('POST', '/events/$live/check-in'),
        hasLength(1),
      );
      vm.dispose();
      status.dispose();
    });

    test('a connection lost mid-send keeps the scan too', () async {
      final offline = Offline(FakeBackend(liveEventId: live));
      final services = testServices(
        auth: signedInAuth(),
        backend: offline.connection,
      );
      final vm = CheckInViewModel(
        events: services.events,
        location: FakeLocationService(),
        locationOptIn: () => false,
        onCheckedIn: () {},
        analytics: services.analytics,
        // The network looks fine, but requests fail (no signal behind Wi-Fi).
        isOnline: () => true,
      );
      offline.connection.online = false;

      await vm.submit(live, FakeBackend.checkInCode(live));
      expect(vm.waitingForConnection, isTrue);
      expect(vm.refusal, isNull);

      offline.connection.online = true;
      await vm.sendPending();
      expect(vm.result, isNotNull);
      vm.dispose();
    });
  });

  test('without a connectivity service the app assumes it is online', () async {
    expect(await const AlwaysConnected().isConnected(), isTrue);
  });
}
