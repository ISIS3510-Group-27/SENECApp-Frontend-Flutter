import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/features/compare_groups/compare_groups_screen.dart';
import 'package:senecapp/features/rso_detail/rso_detail_screen.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  late FakeBackend backend;

  setUp(() => backend = FakeBackend());

  Future<void> openComparison(
    WidgetTester tester, {
    http.Client? client,
  }) async {
    await pumpApp(
      tester,
      testServices(auth: signedInAuth(), backend: client ?? backend.client),
    );
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    final entry = find.text('Compare recommended groups');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label, String name) async {
    final picker = find.byKey(ValueKey(label));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> selectPair(WidgetTester tester) async {
    await choose(tester, 'First organization', 'Viajeros Uniandes');
    await choose(tester, 'Second organization', 'Fotografía Uniandes');
  }

  testWidgets('Profile opens the comparison and selection makes no requests', (
    tester,
  ) async {
    await openComparison(tester);
    expect(find.byType(CompareGroupsScreen), findsOneWidget);
    final before = backend.requestsTo('GET', '/recommendations/groups').length;
    await choose(tester, 'First organization', 'Viajeros Uniandes');

    final second = tester.widget<DropdownButton<int>>(
      find.byKey(const ValueKey('Second organization')),
    );
    expect(second.items!.map((item) => item.value), isNot(contains(3)));
    await choose(tester, 'Second organization', 'Fotografía Uniandes');

    for (final label in [
      'CATEGORY',
      'MEMBERS',
      'DESCRIPTION',
      'RECOMMENDATION REASONS',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find
            .descendant(
              of: find.byType(CompareGroupsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text(label), findsOneWidget);
    }
    expect(
      backend.requestsTo('GET', '/recommendations/groups'),
      hasLength(before),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail and join preserve BQ6 attribution and returning keeps choices',
    (tester) async {
      await openComparison(tester);
      await selectPair(tester);
      final fetches = backend
          .requestsTo('GET', '/recommendations/groups')
          .length;
      final open = find.byKey(const ValueKey('open-compared-group-3'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(RsoDetailScreen), findsOneWidget);
      final view = backend.requestsTo('GET', '/groups/3').single;
      expect(view.url.queryParameters['entry_point'], 'recommendation');
      expect(
        view.url.queryParameters['rec_request_id'],
        FakeBackend.recRequestId,
      );
      await tester.tap(find.text('Join RSO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      final join = backend.requestsTo('POST', '/groups/3/join').single;
      expect(
        jsonDecode(join.body),
        allOf(
          containsPair('entry_point', 'recommendation'),
          containsPair('rec_request_id', FakeBackend.recRequestId),
        ),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, 1500));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('First organization')),
            )
            .value,
        3,
      );
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('Second organization')),
            )
            .value,
        8,
      );
      expect(
        backend.requestsTo('GET', '/recommendations/groups'),
        hasLength(fetches),
      );
    },
  );

  testWidgets('refresh preserves surviving IDs and sends the new request ID', (
    tester,
  ) async {
    var request = 0;
    final client = MockClient((incoming) async {
      final response = await _forward(backend, incoming);
      if (incoming.url.path.endsWith('/recommendations/groups') &&
          response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        data['request_id'] = 'response-${++request}';
        return jsonResponse(data);
      }
      return response;
    });
    await openComparison(tester, client: client);
    await selectPair(tester);
    final refresh = find.text('Refresh recommendations');
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    final expectedId = 'response-$request';
    final open = find.byKey(const ValueKey('open-compared-group-3'));
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(
      backend
          .requestsTo('GET', '/groups/3')
          .single
          .url
          .queryParameters['rec_request_id'],
      expectedId,
    );
  });

  testWidgets('loading is visible and does not duplicate a pending request', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var requests = 0;
    final client = MockClient((incoming) {
      if (incoming.url.path.endsWith('/recommendations/groups') &&
          ++requests == 2) {
        return pending.future;
      }
      return _forward(backend, incoming);
    });
    await pumpApp(tester, testServices(auth: signedInAuth(), backend: client));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Compare recommended groups'));
    await tester.tap(find.text('Compare recommended groups'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(requests, 2);
    pending.complete(
      jsonResponse({
        'request_id': 'pending',
        'model_version': 'v1',
        'items': [],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('failed loading offers a working retry and reports the screen', (
    tester,
  ) async {
    backend.recommenderDown = true;
    await openComparison(tester);
    expect(find.text("Couldn't load this"), findsOneWidget);
    final analytics = tester
        .element(find.byType(CompareGroupsScreen))
        .read<AppServices>()
        .analytics;
    expect(
      analytics.pending.where(
        (event) =>
            event['name'] == 'app_error' && event['screen'] == 'compare_groups',
      ),
      isNotEmpty,
    );
    backend.recommenderDown = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('First organization')), findsOneWidget);
    expect(find.text("Couldn't load this"), findsNothing);
  });

  for (final members in [
    <int>{1, 2, 3, 5, 6},
    <int>{1, 2, 3, 5, 6, 8},
  ]) {
    testWidgets(
      'fewer than two recommendations shows an explanatory state (${members.length})',
      (tester) async {
        backend = FakeBackend(memberIds: members);
        await openComparison(tester);
        expect(
          find.textContaining('You need at least two recommendations'),
          findsOneWidget,
        );
        expect(find.byType(DropdownButton<int>), findsNothing);
      },
    );
  }

  testWidgets('comparison fits a narrow phone with enlarged text', (
    tester,
  ) async {
    await openComparison(tester);
    tester.view.physicalSize = const Size(320, 844);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await selectPair(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<http.Response> _forward(FakeBackend backend, http.Request request) {
  final copy = http.Request(request.method, request.url)
    ..headers.addAll(request.headers)
    ..bodyBytes = request.bodyBytes;
  return backend.client.send(copy).then(http.Response.fromStream);
}
