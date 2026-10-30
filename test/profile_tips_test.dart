import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/core/theme/app_colors.dart';
import 'package:senecapp/data/models/rso.dart';
import 'package:senecapp/data/models/rso_category.dart';
import 'package:senecapp/features/profile_tips/profile_tips_screen.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

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

  Future<FakeBackend> openTips(WidgetTester tester) async {
    final backend = FakeBackend(adminOf: {1});
    final services = testServices(
      auth: signedInAuth(),
      backend: backend.client,
    );
    tester.view.physicalSize = const Size(390, 1400);
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
                  ).push(ProfileTipsScreen.route(tennis)),
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
    return backend;
  }

  testWidgets('lists the missing fields with what BQ4 found', (tester) async {
    final backend = await openTips(tester);

    expect(find.text('5 of 7 profile fields filled'), findsOneWidget);
    expect(find.text('STILL MISSING'), findsOneWidget);
    expect(find.text('Cover photo'), findsOneWidget);
    expect(
      find.text('Profiles with it turn 1.4x more views into saves or joins.'),
      findsOneWidget,
    );
    expect(
      find.text('Use "Change cover photo" on the group page.'),
      findsOneWidget,
    );
    expect(find.text('An upcoming event'), findsOneWidget);
    expect(
      find.text('Not enough profile views yet to say how much it matters.'),
      findsOneWidget,
    );
    expect(backend.requestsTo('GET', '/groups/1/insights/profile'), hasLength(1));
  });

  testWidgets('fields already filled are listed apart', (tester) async {
    await openTips(tester);

    expect(find.text('ALREADY THERE'), findsOneWidget);
    expect(find.text('Instagram link'), findsOneWidget);
    expect(find.text('Website'), findsOneWidget);
  });
}
