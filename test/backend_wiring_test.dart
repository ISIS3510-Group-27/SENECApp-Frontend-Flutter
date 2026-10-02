import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:senecapp/core/widgets/rso_list_tile.dart';
import 'package:senecapp/core/widgets/selectable_chip.dart';
import 'package:senecapp/features/discover/discover_screen.dart';

import 'support/fakes.dart';

/// What the app sends the backend as the student browses. Much of it is
/// analytics, so the exact parameters matter as much as the screens.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeBackend backend;

  Future<void> openApp(WidgetTester tester) async {
    backend = FakeBackend();
    await pumpApp(
      tester,
      testServices(auth: signedInAuth(), backend: backend.client),
    );
  }

  /// The Events screen's list requests, without the semester attendance count
  /// (`starts_after`) the app also asks for.
  List<Map<String, String>> eventListQueries() => [
    for (final r in backend.requestsTo('GET', '/events'))
      if (!r.url.queryParameters.containsKey('starts_after'))
        r.url.queryParameters,
  ];

  Map<String, List<String>> lastSearch() =>
      backend.requestsTo('GET', '/groups').last.url.queryParametersAll;

  group('Discover', () {
    testWidgets('browsing is not logged as a search', (tester) async {
      await openApp(tester);

      expect(lastSearch(), {
        'limit': ['50'],
      });
    });

    testWidgets('a browsed group opens and joins as explore, viewed once', (
      tester,
    ) async {
      await openApp(tester);

      await tester.tap(find.widgetWithText(RsoListTile, 'Viajeros Uniandes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join RSO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      final views = backend.requestsTo('GET', '/groups/3');
      expect(views, hasLength(1), reason: 'each fetch is logged as a view');
      expect(views.single.url.queryParameters['entry_point'], 'explore');
      final join = backend.requestsTo('POST', '/groups/3/join').single;
      expect(jsonDecode(join.body), containsPair('entry_point', 'explore'));
      expect(find.text('✓ Joined - Welcome!'), findsOneWidget);
    });

    testWidgets('typing sends one search, and its results open as search', (
      tester,
    ) async {
      await openApp(tester);
      final field = find.byType(TextField).first;

      for (final text in ['te', 'ten', 'tennis']) {
        await tester.enterText(field, text);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(DiscoverScreen.searchDebounce);
      await tester.pumpAndSettle();

      final searches = backend
          .requestsTo('GET', '/groups')
          .where((r) => r.url.queryParameters.containsKey('q'));
      expect(searches.map((r) => r.url.queryParameters['q']), ['tennis']);

      await tester.tap(find.text('Tennis Uniandes'));
      await tester.pumpAndSettle();
      expect(
        backend
            .requestsTo('GET', '/groups/1')
            .single
            .url
            .queryParameters['entry_point'],
        'search',
      );
    });

    testWidgets('filters are sent only on "Show results"', (tester) async {
      await openApp(tester);
      final searchesBefore = backend.requestsTo('GET', '/groups').length;

      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Official RSOs'));
      await tester.tap(find.text('Tennis'));
      await tester.pumpAndSettle();
      expect(backend.requestsTo('GET', '/groups'), hasLength(searchesBefore));

      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      expect(lastSearch(), {
        'interest_id': ['1'],
        'verified': ['true'],
        'limit': ['50'],
      });
      expect(find.text('1 ORGANIZATION'), findsOneWidget);
    });

    testWidgets('the heart saves from Explore and unsaves', (tester) async {
      await openApp(tester);
      final heart = find.descendant(
        of: find.widgetWithText(RsoListTile, 'Emprendedores Uniandes'),
        matching: find.byType(InkWell),
      );

      await tester.tap(heart.last);
      await tester.pumpAndSettle();
      final save = backend.requestsTo('PUT', '/groups/2/save').single;
      expect(save.url.queryParameters['source'], 'explore');
      expect(backend.savedIds, {2});

      await tester.tap(heart.last);
      await tester.pumpAndSettle();
      expect(backend.requestsTo('DELETE', '/groups/2/save'), hasLength(1));
      expect(backend.savedIds, isEmpty);
    });
  });

  testWidgets('a save on the profile is sent from group_detail', (
    tester,
  ) async {
    await openApp(tester);

    await tester.tap(find.text('Viajeros Uniandes').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    final save = backend.requestsTo('PUT', '/groups/3/save').single;
    expect(save.url.queryParameters['source'], 'group_detail');
    expect(find.byTooltip('Remove from saved'), findsOneWidget);
  });

  group('Notifications', () {
    testWidgets('tapping one records the open and shows its event', (
      tester,
    ) async {
      await openApp(tester);

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Round Robin Tournament is this Saturday.'));
      await tester.pumpAndSettle();

      expect(
        backend.requestsTo('POST', '/me/notifications/1/open'),
        hasLength(1),
      );
      // About event 1, so it opens the event, as tapping the push does.
      expect(
        backend.requestsTo('GET', '/events/1').single.url.queryParameters,
        {'entry_point': 'notification'},
      );
    });

    testWidgets('"Mark all read" dismisses only the unread ones', (
      tester,
    ) async {
      await openApp(tester);

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      final dismissed = backend.requests
          .where((r) => r.url.path.endsWith('/dismiss'))
          .map((r) => r.url.pathSegments[4]);
      expect(dismissed, unorderedEquals(['1', '2', '3']));
      expect(
        backend.requests.where((r) => r.url.path.endsWith('/open')),
        isEmpty,
        reason: 'clearing the inbox is not an interaction (BQ8)',
      );
    });
  });

  group('Events', () {
    testWidgets('"My RSOs" asks the backend for my groups only', (
      tester,
    ) async {
      await openApp(tester);

      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      expect(eventListQueries().last, isNot(contains('mine')));

      await tester.tap(find.widgetWithText(SelectableChip, 'My RSOs'));
      await tester.pumpAndSettle();

      expect(eventListQueries().last['mine'], 'true');
      // The student's groups are Tennis, Emprendedores and AI & ML.
      expect(find.text('LLM Workshop: Build Your Own Agent'), findsOneWidget);
      expect(find.text('Round Robin Tournament'), findsOneWidget);
      // Third in the list, below the fold at phone size.
      await tester.scrollUntilVisible(find.text('Pitch Night #14'), 300);
      expect(find.text('Pitch Night #14'), findsOneWidget);
      expect(
        find.text('Open Auditions: Obra de Semestre', skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('an event opens its page, and its host as an event entry', (
      tester,
    ) async {
      await openApp(tester);

      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Pitch Night #14'), 300);
      await tester.tap(find.text('Pitch Night #14'));
      await tester.pumpAndSettle();

      expect(
        backend.requestsTo('GET', '/events/3').single.url.queryParameters,
        {'entry_point': 'events'},
      );

      await tester.tap(find.text('Emprendedores Uniandes'));
      await tester.pumpAndSettle();

      expect(
        backend
            .requestsTo('GET', '/groups/2')
            .single
            .url
            .queryParameters['entry_point'],
        'event',
      );
    });
  });

  testWidgets('My RSOs lists the groups the backend has for the student', (
    tester,
  ) async {
    await openApp(tester);

    await tester.tap(find.text('My RSOs').last);
    await tester.pumpAndSettle();

    expect(find.text('Tennis Uniandes'), findsOneWidget);
    expect(find.text('Emprendedores Uniandes'), findsOneWidget);
    expect(find.text('AI & Machine Learning'), findsOneWidget);
    expect(find.text('Viajeros Uniandes'), findsNothing);
  });
}
