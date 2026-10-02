import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:senecapp/data/location/location_service.dart';
import 'package:senecapp/data/models/check_in.dart';
import 'package:senecapp/features/check_in/check_in_screen.dart';

import 'support/fakes.dart';

/// QR check-in: the camera reads the venue's code, the GPS (with consent)
/// confirms the student is there. Organizers show the code.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Event 2, the AI & ML workshop, is on right now; the student belongs to
  // AI & ML (group 5).
  const liveEvent = 2;
  const workshop = 'LLM Workshop: Build Your Own Agent';
  final validCode =
      'senecapp://check-in?event_id=$liveEvent'
      '&code=${FakeBackend.checkInCode(liveEvent)}';

  late FakeBackend backend;
  late FakeLocationService location;
  late FakeQrCamera camera;

  Future<void> openApp(
    WidgetTester tester, {
    bool optedIn = true,
    Set<int> adminOf = const {},
  }) async {
    backend = FakeBackend(
      me: {...sofiaJson, 'location_opt_in': optedIn},
      liveEventId: liveEvent,
      adminOf: adminOf,
    );
    location = FakeLocationService();
    camera = FakeQrCamera();
    await pumpApp(
      tester,
      testServices(
        auth: signedInAuth(),
        backend: backend.client,
        location: location,
        camera: camera,
      ),
    );
  }

  Future<void> openEvent(WidgetTester tester, String title) async {
    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(title), 300);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> scan(WidgetTester tester, String text) async {
    camera.scan(text);
    await tester.pumpAndSettle();
  }

  List<Map<String, dynamic>> checkIns(int eventId) => [
    for (final r in backend.requestsTo('POST', '/events/$eventId/check-in'))
      jsonDecode(r.body) as Map<String, dynamic>,
  ];

  testWidgets('scanning the code checks in, with the position', (tester) async {
    await openApp(tester);
    await openEvent(tester, workshop);

    await tester.tap(find.text('Check in with QR'));
    await tester.pumpAndSettle();
    expect(camera.showing, isTrue);
    await scan(tester, validCode);

    expect(location.reads, 1);
    expect(checkIns(liveEvent).single, {
      'code': FakeBackend.checkInCode(liveEvent),
      'latitude': 4.6026,
      'longitude': -74.0649,
    });
    expect(find.text("You're checked in!"), findsOneWidget);
    expect(find.textContaining('Confirmed 0 m from the venue'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('You checked in'), findsOneWidget);
    expect(find.text('Check in with QR'), findsNothing);
  });

  testWidgets('without location consent only the code is sent', (tester) async {
    await openApp(tester, optedIn: false);
    await openEvent(tester, workshop);

    await tester.tap(find.text('Check in with QR'));
    await tester.pumpAndSettle();
    await scan(tester, validCode);

    expect(location.reads, 0);
    expect(checkIns(liveEvent).single, {
      'code': FakeBackend.checkInCode(liveEvent),
    });
    expect(find.text("You're checked in!"), findsOneWidget);
  });

  testWidgets('codes that are not for this event are not sent', (tester) async {
    await openApp(tester);
    await openEvent(tester, workshop);
    await tester.tap(find.text('Check in with QR'));
    await tester.pumpAndSettle();

    await scan(tester, 'https://uniandes.edu.co');
    expect(find.text("That isn't a SENECApp check-in code."), findsOneWidget);

    await scan(tester, 'senecapp://check-in?event_id=3&code=ZZZ');
    expect(find.text('That code is for a different event.'), findsOneWidget);

    expect(camera.showing, isTrue, reason: 'scanning carries on');
    expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets("the backend's refusal is shown, and scanning can resume", (
    tester,
  ) async {
    await openApp(tester);
    // Across town, far from Mario Laserna.
    location.result = const LocationResult.found(4.70, -74.05);
    await openEvent(tester, workshop);
    await tester.tap(find.text('Check in with QR'));
    await tester.pumpAndSettle();

    await scan(tester, validCode);

    expect(find.text("Couldn't check you in"), findsOneWidget);
    expect(
      find.text('You seem to be too far from the event to check in'),
      findsOneWidget,
    );

    await tester.tap(find.text('Scan again'));
    await tester.pumpAndSettle();
    expect(camera.showing, isTrue);
  });

  testWidgets('the code can be typed when the camera fails', (tester) async {
    await openApp(tester, optedIn: false);
    await openEvent(tester, workshop);
    await tester.tap(find.text('Check in with QR'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Type the code instead'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      FakeBackend.checkInCode(liveEvent),
    );
    await tester.tap(find.widgetWithText(InkWell, 'Check in'));
    await tester.pumpAndSettle();

    expect(checkIns(liveEvent).single['code'], 'K7Q2X2');
    expect(find.text("You're checked in!"), findsOneWidget);
  });

  testWidgets('before the window opens it says when', (tester) async {
    await openApp(tester);
    await openEvent(tester, 'Pitch Night #14');

    expect(find.textContaining('Check-in opens at'), findsOneWidget);
    expect(find.text('Check in with QR'), findsNothing);
  });

  testWidgets('the Events tab scanner works for any event', (tester) async {
    await openApp(tester);
    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Scan check-in code'));
    await tester.pumpAndSettle();
    expect(find.text('Scan the code at any event'), findsOneWidget);
    await scan(tester, validCode);

    expect(checkIns(liveEvent), hasLength(1));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('SENECApp Events'), findsOneWidget);
  });

  group('Organizers', () {
    testWidgets('an admin can show the QR code and the code', (tester) async {
      await openApp(tester, adminOf: {5});
      await openEvent(tester, workshop);

      await tester.tap(find.text('Show check-in QR'));
      await tester.pumpAndSettle();

      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.semanticsLabel, 'Check-in QR code for $workshop');
      expect(find.text('K7Q2X2'), findsOneWidget);
    });

    testWidgets('other members just get no button', (tester) async {
      await openApp(tester);
      await openEvent(tester, workshop);

      expect(
        backend.requestsTo('GET', '/events/$liveEvent/check-in-code'),
        hasLength(1),
      );
      expect(find.text('Show check-in QR'), findsNothing);
    });

    testWidgets("non-members aren't even asked", (tester) async {
      await openApp(tester, adminOf: {3});
      // Viajeros (group 3) hosts the trip; the student isn't a member.
      await openEvent(tester, 'Trip to Salento & Coffee Region');

      expect(backend.requestsTo('GET', '/events/4/check-in-code'), isEmpty);
      expect(find.text('Show check-in QR'), findsNothing);
    });
  });

  test('reads check-in QR codes and nothing else', () {
    final payload = CheckInPayload.tryParse(
      ' senecapp://check-in?event_id=12&code=AB3X9K ',
    );
    expect(payload?.eventId, 12);
    expect(payload?.code, 'AB3X9K');

    for (final other in [
      'https://senecapp.co/check-in?event_id=12&code=AB',
      'senecapp://join?event_id=12&code=AB',
      'senecapp://check-in?event_id=twelve&code=AB',
      'senecapp://check-in?event_id=12',
      'WIFI:S:Uniandes;;',
    ]) {
      expect(CheckInPayload.tryParse(other), isNull, reason: other);
    }
  });

  testWidgets('backing out of the scanner reports no check-in', (tester) async {
    await openApp(tester);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    final result = navigator.push(CheckInScreen.route());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });
}
