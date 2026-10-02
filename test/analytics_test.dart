import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/core/ids.dart';
import 'package:senecapp/core/widgets/rso_list_tile.dart';
import 'package:senecapp/data/analytics/analytics.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/api/client_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// The events the app reports itself: screen views with load times (BQ1,
/// BQ11, BQ14), errors (BQ1, BQ14) and the join form (BQ7).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  group('Analytics', () {
    late FakeBackend backend;
    late Analytics analytics;

    Analytics build({String platform = 'android', AnalyticsStore? store}) {
      final auth = signedInAuth();
      final context = ClientContext(
        appVersion: '1.0.0',
        platform: platform,
        deviceModel: 'Google Pixel 8',
        osVersion: '14',
      );
      return Analytics(
        api: ApiClient(
          baseUrl: 'http://test/api/v1',
          auth: auth,
          context: context,
          httpClient: backend.client,
        ),
        context: context,
        store: store,
      );
    }

    setUp(() {
      backend = FakeBackend();
      analytics = build();
    });

    test('events carry the taxonomy envelope', () {
      analytics.screenView(
        Screens.discover,
        loadTime: const Duration(milliseconds: 842),
      );

      final event = analytics.pending.single;
      expect(event['event_id'], matches(uuid));
      expect(event['name'], 'screen_view');
      expect(DateTime.parse(event['occurred_at'] as String).isUtc, isTrue);
      expect(event['session_id'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(event, containsPair('screen', 'discover'));
      expect(event, containsPair('app', 'flutter'));
      expect(event, containsPair('app_version', '1.0.0'));
      expect(event, containsPair('platform', 'android'));
      expect(event, containsPair('device_model', 'Google Pixel 8'));
      expect(event, containsPair('os_version', '14'));
      expect(event['properties'], {'load_time_ms': 842});
    });

    test('a browser is not sent as a platform the backend rejects', () {
      analytics = build(platform: 'web')..screenView(Screens.discover);

      expect(analytics.pending.single.containsKey('platform'), isFalse);
    });

    test('errors say where, what and whether the app crashed', () {
      analytics
        ..screenView(Screens.freeNow)
        ..error(const ApiException(503, 'Service unavailable'))
        ..error(StateError('boom'), screen: Screens.events, fatal: true);

      expect(analytics.pending[1]['screen'], 'free_now');
      expect(analytics.pending[1]['properties'], {
        'feature': 'free_now',
        'error_type': 'ApiException',
        'fatal': false,
        'status_code': 503,
        'message': 'Service unavailable',
      });
      // Not the backend's text: no message, it could hold personal data.
      expect(analytics.pending[2]['properties'], {
        'feature': 'events',
        'error_type': 'StateError',
        'fatal': true,
      });
    });

    test('a flush sends the queue and empties it', () async {
      analytics
        ..screenView(Screens.discover)
        ..joinFormOpened(groupId: 3, joinAttemptId: 'a1');
      await analytics.flush();

      expect(backend.analyticsEvents.map((e) => e['name']), [
        'screen_view',
        'join_form_opened',
      ]);
      expect(analytics.pending, isEmpty);
      final post = backend.requestsTo('POST', '/analytics/events').single;
      expect(post.headers['Authorization'], 'Bearer test-token');
    });

    test('offline, events wait for the next flush', () async {
      analytics.screenView(Screens.discover);
      backend.offline = true;
      await analytics.flush();
      expect(analytics.pending, hasLength(1));

      backend.offline = false;
      await analytics.flush();
      expect(analytics.pending, isEmpty);
      expect(backend.analyticsEvents, hasLength(1));
    });

    test('big queues go out in batches of 500', () async {
      for (var i = 0; i < 1200; i++) {
        analytics.screenView(Screens.discover);
      }
      await analytics.flush();

      final batches = [
        for (final r in backend.requestsTo('POST', '/analytics/events'))
          ((jsonDecode(r.body) as Map)['events'] as List).length,
      ];
      expect(batches, [500, 500, 200]);
    });

    test('the queue survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      backend.offline = true;
      build(
        store: PrefsAnalyticsStore(prefs),
      ).error(StateError('crash'), screen: Screens.events, fatal: true);

      final nextRun = build(store: PrefsAnalyticsStore(prefs));
      await nextRun.restore();
      expect(nextRun.pending.single['name'], 'app_error');

      backend.offline = false;
      await nextRun.flush();
      expect(backend.analyticsEvents.single['properties']['fatal'], isTrue);
    });
  });

  test('ids are random version 4 UUIDs', () {
    final ids = {for (var i = 0; i < 100; i++) newUuid()};
    expect(ids, hasLength(100));
    expect(ids, everyElement(matches(uuid)));
  });

  group('In the app', () {
    late FakeBackend backend;
    late AppServices services;

    Future<void> openApp(WidgetTester tester) async {
      backend = FakeBackend();
      services = testServices(auth: signedInAuth(), backend: backend.client);
      await pumpApp(tester, services);
    }

    List<Map<String, dynamic>> named(String name) => [
      for (final e in services.analytics.pending)
        if (e['name'] == name) e,
    ];

    List<String?> viewedScreens() => [
      for (final e in named('screen_view')) e['screen'] as String?,
    ];

    testWidgets('only the tab on screen counts as viewed', (tester) async {
      await openApp(tester);

      // Every tab is built at launch; only Discover is seen.
      expect(viewedScreens(), ['discover']);
      expect(
        named('screen_view').single['properties'],
        contains('load_time_ms'),
      );

      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle();

      expect(viewedScreens(), ['discover', 'events', 'discover']);
      // Coming back to a loaded screen is a view, but not a load time.
      expect(named('screen_view').last['properties'], isEmpty);
    });

    testWidgets('pushed screens count when opened', (tester) async {
      await openApp(tester);

      await tester.tap(find.widgetWithText(RsoListTile, 'Viajeros Uniandes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();

      expect(viewedScreens(), ['discover', 'group_detail', 'notifications']);
    });

    testWidgets('the join form is a step of its own (BQ7)', (tester) async {
      await openApp(tester);
      await tester.tap(find.widgetWithText(RsoListTile, 'Viajeros Uniandes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Join RSO'));
      await tester.pumpAndSettle();

      final opened = named('join_form_opened').single;
      final attempt = opened['properties']['join_attempt_id'] as String;
      expect(opened['properties']['group_id'], 3);
      expect(attempt, matches(uuid));
      expect(viewedScreens().last, 'join_form');
      expect(backend.requestsTo('POST', '/groups/3/join'), isEmpty);

      await tester.enterText(find.byType(TextField), 'I love road trips');
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      final join = backend.requestsTo('POST', '/groups/3/join').single;
      expect(jsonDecode(join.body), {
        'entry_point': 'explore',
        'join_attempt_id': attempt,
        'motivation': 'I love road trips',
      });
      expect(find.text('✓ Joined - Welcome!'), findsOneWidget);
    });

    testWidgets('closing the form is an abandoned attempt', (tester) async {
      await openApp(tester);
      await tester.tap(find.widgetWithText(RsoListTile, 'Viajeros Uniandes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Join RSO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(named('join_form_opened'), hasLength(1));
      expect(backend.requestsTo('POST', '/groups/3/join'), isEmpty);
      expect(find.text('Join RSO'), findsOneWidget);
    });

    testWidgets('an error the student sees is reported', (tester) async {
      backend = FakeBackend()..failing.add('/groups');
      services = testServices(auth: signedInAuth(), backend: backend.client);
      await pumpApp(tester, services);

      final error = named('app_error').single;
      expect(error['screen'], 'discover');
      expect(error['properties'], {
        'feature': 'explore',
        'error_type': 'ApiException',
        'fatal': false,
        'status_code': 500,
        'message': 'Internal Server Error',
      });
      // The error screen still counts as the screen being viewed.
      expect(viewedScreens(), ['discover']);
    });

    testWidgets('signing out sends what is queued first', (tester) async {
      await openApp(tester);
      expect(services.analytics.pending, isNotEmpty);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.fling(find.text('INTERESTS'), const Offset(0, -1000), 2000);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      final post = backend.requestsTo('POST', '/analytics/events').first;
      // Still this student's token: the events are theirs.
      expect(post.headers['Authorization'], 'Bearer test-token');
      expect(
        backend.analyticsEvents.map((e) => e['screen']),
        containsAll(['discover', 'profile']),
      );
    });
  });
}
