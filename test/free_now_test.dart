import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:senecapp/data/location/location_service.dart';
import 'package:senecapp/data/models/free_now.dart';
import 'package:senecapp/data/models/schedule_block.dart';
import 'package:senecapp/features/free_now/free_now_screen.dart';
import 'package:senecapp/features/schedule/schedule_screen.dart';

import 'support/fakes.dart';

/// "Free right now" (context-aware: schedule, time and GPS), and the class
/// schedule behind it.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeBackend backend;
  late FakeLocationService location;

  setUp(() => location = FakeLocationService());

  Future<void> openApp(
    WidgetTester tester, {
    bool optedIn = true,
    bool withSchedule = true,
  }) async {
    backend = FakeBackend(
      me: {...sofiaJson, 'location_opt_in': optedIn},
      withSchedule: withSchedule,
    );
    await pumpApp(
      tester,
      testServices(
        auth: signedInAuth(),
        backend: backend.client,
        location: location,
      ),
    );
  }

  Future<void> openFreeNow(WidgetTester tester) async {
    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Free right now?'));
    await tester.pumpAndSettle();
  }

  List<Map<String, String>> freeNowQueries() => [
    for (final r in backend.requestsTo(
      'GET',
      '/recommendations/events/free-now',
    ))
      r.url.queryParameters,
  ];

  testWidgets('uses GPS when allowed and shows what fits the free block', (
    tester,
  ) async {
    await openApp(tester);
    await openFreeNow(tester);

    expect(location.reads, 1);
    expect(freeNowQueries().single, {
      'latitude': '4.6026',
      'longitude': '-74.0649',
      'limit': '5',
    });
    expect(find.text('FREE NOW'), findsOneWidget);
    expect(find.text('70 min before your next class'), findsOneWidget);
    expect(find.text('Near Edificio Mario Laserna'), findsOneWidget);
    expect(find.text('LLM Workshop: Build Your Own Agent'), findsOneWidget);
    expect(find.text('4 min walk'), findsOneWidget);
    expect(find.text('From one of your groups'), findsOneWidget);
  });

  testWidgets('a suggestion opens as a free_now view of that answer', (
    tester,
  ) async {
    await openApp(tester);
    await openFreeNow(tester);

    await tester.tap(find.text('LLM Workshop: Build Your Own Agent'));
    await tester.pumpAndSettle();

    expect(find.text('HOSTED BY'), findsOneWidget);
    expect(backend.requestsTo('GET', '/events/2').single.url.queryParameters, {
      'entry_point': 'free_now',
      'rec_request_id': FakeBackend.freeNowRequestId,
    });
    expect(freeNowQueries(), hasLength(1));
  });

  testWidgets('asks before using location, and "Not now" never reads it', (
    tester,
  ) async {
    await openApp(tester, optedIn: false);
    await openFreeNow(tester);

    expect(find.text('Use your location?'), findsOneWidget);
    expect(freeNowQueries(), isEmpty, reason: 'nothing is shown yet');

    await tester.tap(find.text('Not now, use my schedule'));
    await tester.pumpAndSettle();

    expect(location.reads, 0);
    expect(freeNowQueries().single, {'limit': '5'});
    expect(
      find.text('Near Edificio Mario Laserna, from your class schedule'),
      findsOneWidget,
    );
    expect(find.text('Use my location'), findsOneWidget);
  });

  testWidgets('"Use my location" records consent, then reads GPS', (
    tester,
  ) async {
    await openApp(tester, optedIn: false);
    await openFreeNow(tester);

    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    final consent = backend.requestsTo('PATCH', '/me').single;
    expect(jsonDecode(consent.body), {'location_opt_in': true});
    expect(location.reads, 1);
    expect(freeNowQueries().single, contains('latitude'));
  });

  testWidgets('a denied permission falls back to the schedule', (tester) async {
    location.result = const LocationResult.failed(LocationProblem.denied);
    await openApp(tester);
    await openFreeNow(tester);

    expect(freeNowQueries().single, {'limit': '5'});
    expect(
      find.textContaining('Location permission was denied.'),
      findsOneWidget,
    );

    location.result = const LocationResult.found(4.6026, -74.0649);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(freeNowQueries().last, contains('latitude'));
    expect(find.text('Near Edificio Mario Laserna'), findsOneWidget);
  });

  testWidgets('a blocked permission points to the settings', (tester) async {
    location.result = const LocationResult.failed(
      LocationProblem.deniedForever,
    );
    await openApp(tester);
    await openFreeNow(tester);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(location.settingsOpened, [LocationProblem.deniedForever]);
  });

  testWidgets('without classes it offers to add them, then asks again', (
    tester,
  ) async {
    await openApp(tester, optedIn: false, withSchedule: false);
    await openFreeNow(tester);
    await tester.tap(find.text('Not now, use my schedule'));
    await tester.pumpAndSettle();

    expect(find.text("We don't know where you are"), findsOneWidget);
    await tester.tap(find.text('Add schedule'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleScreen), findsOneWidget);

    await tester.tap(find.text('+ Add class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tue'));
    await tester.tap(find.text('ML'));
    await tester.enterText(find.byType(TextField), 'Física I');
    await tester.tap(find.text('Add class').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();

    final saved = backend.requestsTo('PUT', '/me/schedule').single;
    expect(jsonDecode(saved.body), {
      'blocks': [
        {
          'weekday': 1,
          'start_time': '08:30:00',
          'end_time': '09:50:00',
          'title': 'Física I',
          'building_id': 1,
        },
      ],
    });

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(FreeNowScreen), findsOneWidget);
    expect(freeNowQueries(), hasLength(2));
    expect(
      find.text('Near Edificio Mario Laserna, from your class schedule'),
      findsOneWidget,
    );
  });

  group('Class schedule', () {
    Future<void> openSchedule(WidgetTester tester) async {
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Class schedule'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the saved classes by day', (tester) async {
      await openApp(tester);
      await openSchedule(tester);

      expect(find.text('MONDAY'), findsOneWidget);
      expect(find.text('Cálculo II · Edificio Mario Laserna'), findsOneWidget);
    });

    testWidgets('catches overlapping classes before saving', (tester) async {
      await openApp(tester);
      await openSchedule(tester);

      // Monday 8:30-9:50 is taken by Cálculo II.
      await tester.tap(find.text('+ Add class'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add class').last);
      await tester.pumpAndSettle();

      expect(
        find.text('That overlaps another class that day.'),
        findsOneWidget,
      );
    });

    testWidgets('asks before throwing away unsaved changes', (tester) async {
      await openApp(tester);
      await openSchedule(tester);

      await tester.tap(find.byTooltip('Remove class'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(ScheduleScreen), findsNothing);
      expect(backend.requestsTo('PUT', '/me/schedule'), isEmpty);
    });
  });

  testWidgets('location consent can be withdrawn from Profile', (tester) async {
    await openApp(tester);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final change = backend.requestsTo('PATCH', '/me').single;
    expect(jsonDecode(change.body), {'location_opt_in': false});
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  group('models', () {
    test('reads a free-now answer', () {
      final result = FreeNowSuggestions.fromJson({
        'request_id': 'r1',
        'free_block': null,
        'schedule_known': true,
        'location': {'building': null, 'source': 'schedule', 'on_campus': null},
        'items': <Object>[],
        'message': 'No more free time between classes today.',
      });

      expect(result.hasFreeTime, isFalse);
      expect(result.locationSource, LocationSource.schedule);
      expect(result.message, 'No more free time between classes today.');
    });

    test('schedule blocks round-trip and detect overlaps', () {
      final block = ScheduleBlock.fromJson({
        'id': 3,
        'weekday': 2,
        'start_time': '14:30:00',
        'end_time': '15:50:00',
        'title': '  ',
        'building': {'id': 4, 'code': 'AU', 'name': 'Edificio Aulas'},
      });

      expect(block.toJson(), {
        'weekday': 2,
        'start_time': '14:30:00',
        'end_time': '15:50:00',
        'title': null,
        'building_id': 4,
      });
      expect(
        block.overlaps(
          const ScheduleBlock(
            weekday: 2,
            start: TimeOfDay(hour: 15, minute: 50),
            end: TimeOfDay(hour: 17, minute: 0),
          ),
        ),
        isFalse,
        reason: 'back-to-back classes do not overlap',
      );
      expect(
        block.overlaps(
          const ScheduleBlock(
            weekday: 2,
            start: TimeOfDay(hour: 15, minute: 0),
            end: TimeOfDay(hour: 16, minute: 0),
          ),
        ),
        isTrue,
      );
    });
  });
}
