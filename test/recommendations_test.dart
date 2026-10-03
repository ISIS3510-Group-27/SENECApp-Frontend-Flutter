import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:senecapp/core/widgets/rso_list_tile.dart';
import 'package:senecapp/data/models/recommendation.dart';
import 'package:senecapp/features/discover/discover_screen.dart';
import 'package:senecapp/features/recommendations/recommendations_screen.dart';

import 'support/fakes.dart';

/// The recommender on Discover: what it shows, and that every view and join
/// it leads to is attributed to the list it came from (BQ2, BQ6).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeBackend backend;

  Future<void> openApp(WidgetTester tester) async {
    await pumpApp(
      tester,
      testServices(auth: signedInAuth(), backend: backend.client),
    );
  }

  setUp(() => backend = FakeBackend());

  int recommendationFetches() =>
      backend.requestsTo('GET', '/recommendations/groups').length;

  testWidgets('Discover shows the picks with their top reason', (tester) async {
    await openApp(tester);

    expect(find.text('RECOMMENDED FOR YOU'), findsOneWidget);
    expect(find.text('Matches your interests: Travel'), findsOneWidget);
    expect(find.text('Verified group'), findsOneWidget);
    // Only the strongest reason fits on a card.
    expect(find.text('Popular on campus'), findsNothing);
  });

  testWidgets('recommendations are fetched once per visit', (tester) async {
    await openApp(tester);

    // Searching hides them; clearing the search brings the same list back.
    await tester.enterText(find.byType(TextField).first, 'tennis');
    await tester.pump(DiscoverScreen.searchDebounce);
    await tester.pumpAndSettle();
    expect(find.text('RECOMMENDED FOR YOU'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('RECOMMENDED FOR YOU'), findsOneWidget);

    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();

    expect(recommendationFetches(), 1);
  });

  testWidgets('a recommended group is viewed and joined as a recommendation', (
    tester,
  ) async {
    await openApp(tester);

    await tester.tap(find.text('Matches your interests: Travel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join RSO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    final view = backend.requestsTo('GET', '/groups/3').single.url;
    expect(view.queryParameters, {
      'entry_point': 'recommendation',
      'rec_request_id': FakeBackend.recRequestId,
    });
    final join = backend.requestsTo('POST', '/groups/3/join').single;
    expect(
      jsonDecode(join.body),
      allOf(
        containsPair('entry_point', 'recommendation'),
        containsPair('rec_request_id', FakeBackend.recRequestId),
      ),
    );

    // Back on Discover, a group the student joined is no longer suggested.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Matches your interests: Travel'), findsNothing);
    expect(find.text('Verified group'), findsOneWidget);
  });

  testWidgets('"See all" lists every reason without asking again', (
    tester,
  ) async {
    await openApp(tester);

    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();

    expect(find.byType(RecommendationsScreen), findsOneWidget);
    expect(find.text('Matches your interests: Travel'), findsOneWidget);
    expect(find.text('Popular on campus'), findsOneWidget);
    expect(find.byType(RsoListTile), findsNWidgets(3));

    await tester.tap(find.text('Fotografía Uniandes'));
    await tester.pumpAndSettle();

    expect(backend.requestsTo('GET', '/groups/8').single.url.queryParameters, {
      'entry_point': 'recommendation',
      'rec_request_id': FakeBackend.recRequestId,
    });
    expect(recommendationFetches(), 1);
  });

  testWidgets('saves from the recommendations list say so', (tester) async {
    await openApp(tester);

    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.widgetWithText(RsoListTile, 'Teatro Los Andes'),
            matching: find.byType(InkWell),
          )
          .last,
    );
    await tester.pumpAndSettle();

    expect(
      backend.requestsTo('PUT', '/groups/6/save').single.url.queryParameters,
      {'source': 'recommendations'},
    );
  });

  testWidgets('popular groups stand in when the recommender is down', (
    tester,
  ) async {
    backend.recommenderDown = true;
    await openApp(tester);

    expect(find.text('RECOMMENDED FOR YOU'), findsNothing);
    expect(find.text('FEATURED'), findsOneWidget);

    // Opening one is browsing, not a recommendation.
    await tester.tap(find.text('Emprendedores Uniandes').first);
    await tester.pumpAndSettle();
    expect(backend.requestsTo('GET', '/groups/2').single.url.queryParameters, {
      'entry_point': 'explore',
    });
  });

  testWidgets('pull to refresh asks for a new list', (tester) async {
    await openApp(tester);

    await tester.fling(find.text('SENECApp'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(recommendationFetches(), 2);
  });

  test('reads the recommender answer', () {
    final recommendations = GroupRecommendations.fromJson({
      'request_id': 'abc',
      'model_version': 'v7',
      'items': [
        {
          'group': {
            'id': 3,
            'name': 'Viajeros Uniandes',
            'category': {'id': 5, 'slug': 'travel', 'label': 'Travel'},
            'description': 'Trips.',
            'color': '#00C9A7',
            'image_url': null,
            'verified': false,
            'is_active': true,
            'member_count': 207,
            'tags': <Object>[],
            'next_event': null,
            'is_member': false,
            'is_saved': false,
          },
          'score': 0.71,
          'reasons': ['Popular on campus'],
        },
      ],
    });

    expect(recommendations.requestId, 'abc');
    expect(recommendations.modelVersion, 'v7');
    expect(recommendations.items.single.group.name, 'Viajeros Uniandes');
    expect(recommendations.items.single.reasons, ['Popular on campus']);
  });
}
