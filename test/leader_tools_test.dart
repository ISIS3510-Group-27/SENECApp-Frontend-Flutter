import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/core/theme/app_colors.dart';
import 'package:senecapp/data/models/leader_insights.dart';
import 'package:senecapp/data/models/rso.dart';
import 'package:senecapp/data/models/rso_category.dart';
import 'package:senecapp/features/create_event/create_event_screen.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeBackend backend;

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

  Future<void> openCreateEvent(WidgetTester tester) async {
    backend = FakeBackend(adminOf: {1});
    final services = testServices(
      auth: signedInAuth(),
      backend: backend.client,
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Provider<AppServices>.value(
        value: services,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(CreateEventScreen.route(tennis)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder formScrollable() => find
      .descendant(
        of: find.byType(CreateEventScreen),
        matching: find.byType(Scrollable),
      )
      .first;

  testWidgets('the form shows when members are free and BQ3', (tester) async {
    await openCreateEvent(tester);

    expect(find.text('3 of 3 members free · past events 75% full'), findsOneWidget);
    expect(find.textContaining('around 12:00'), findsOneWidget);
    expect(
      backend
          .requestsTo('GET', '/groups/1/insights/best-times')
          .single
          .url
          .queryParameters,
      {'duration_minutes': '120'},
    );
  });

  testWidgets('a suggested time fills the form and publishes', (tester) async {
    await openCreateEvent(tester);

    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Doubles night');
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Publish event'),
      formScrollable(),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish event'));
    await tester.pumpAndSettle();

    final body =
        jsonDecode(backend.requestsTo('POST', '/groups/1/events').single.body)
            as Map<String, dynamic>;
    expect(body['title'], 'Doubles night');
    expect(DateTime.parse(body['starts_at'] as String), FakeBackend.bestSlot);
    expect(
      DateTime.parse(body['ends_at'] as String),
      FakeBackend.bestSlot.add(const Duration(hours: 2)),
    );
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a leader sees the tools on the group page', (tester) async {
    backend = FakeBackend(adminOf: {1});
    await pumpApp(
      tester,
      testServices(auth: signedInAuth(), backend: backend.client),
    );

    await tester.tap(find.text('My RSOs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tennis Uniandes'));
    await tester.pumpAndSettle();

    expect(
      find.text('You lead this group', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Create event', skipOffstage: false), findsOneWidget);
  });

  test('insights parse from the backend', () {
    final slot = SuggestedSlot.fromJson({
      'weekday': 3,
      'start_time': '18:00',
      'end_time': '19:30',
      'free_members': 9,
      'free_ratio': 0.75,
      'attendance_rate': null,
      'score': 0.75,
      'next_starts_at': '2026-10-08T18:00:00-05:00',
    });

    expect(slot.length, const Duration(minutes: 90));
    expect(slot.nextStartsAt, DateTime.utc(2026, 10, 8, 23));
    expect(slot.attendanceRate, isNull);
  });
}
