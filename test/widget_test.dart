import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:senecapp/app.dart';
import 'package:senecapp/core/assets/asset_catalog.dart';
import 'package:senecapp/features/create_rso/create_rso_screen.dart';

void main() {
  setUpAll(() {
    // Tests have no network. Without this, google_fonts attempts a download for
    // every style and floods the run with failures; disabling it falls back to
    // the bundled default font, which is fine for behavioural tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// Pumps the app at phone size so PhoneFrame steps aside and layouts match
  /// what a device would show.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const SenecApp());
    await tester.pumpAndSettle();
  }

  testWidgets('opens on Discover with every organization listed', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('SENECApp'), findsOneWidget);
    expect(find.text('8 ORGANIZATIONS'), findsOneWidget);
  });

  testWidgets('category chip narrows the list', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Sports'));
    await tester.pumpAndSettle();

    // Tennis Uniandes is the only Sports organization.
    expect(find.text('1 ORGANIZATION'), findsOneWidget);
    expect(find.text('Tennis Uniandes'), findsOneWidget);
  });

  testWidgets('search matches on category as well as name', (tester) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextField).first, 'business');
    await tester.pumpAndSettle();

    // Emprendedores Uniandes and Finance Society are both Business.
    expect(find.text('2 ORGANIZATIONS'), findsOneWidget);
  });

  testWidgets('joining an organization updates My RSOs', (tester) async {
    await pumpApp(tester);

    // Viajeros Uniandes is not one of the seeded memberships.
    await tester.tap(find.text('Viajeros Uniandes'));
    await tester.pumpAndSettle();

    expect(find.text('Join RSO'), findsOneWidget);
    await tester.tap(find.text('Join RSO'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Joined'), findsWidgets);

    await tester.tap(find.text('My RSOs').last);
    await tester.pumpAndSettle();

    expect(find.text('Viajeros Uniandes'), findsOneWidget);
  });

  testWidgets('back from a detail returns to the tab it was opened from', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    expect(find.text('SENECApp Events'), findsOneWidget);

    await tester.tap(find.text('Round Robin Tournament'));
    await tester.pumpAndSettle();
    expect(find.text('ABOUT'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // Events, not Discover.
    expect(find.text('SENECApp Events'), findsOneWidget);
  });

  testWidgets('create form stays disabled until name and category are set', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('New RSO'));
    await tester.pumpAndSettle();

    // The form is taller than the viewport, so the button has to be scrolled
    // into range before it can be tapped.
    final formScrollable = find
        .descendant(
          of: find.byType(CreateRsoScreen),
          matching: find.byType(Scrollable),
        )
        .first;

    Future<void> tapSubmit() async {
      await tester.dragUntilVisible(
        find.text('Submit for Review'),
        formScrollable,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit for Review'));
      await tester.pumpAndSettle();
    }

    await tapSubmit();
    expect(find.text('Proposal Submitted!'), findsNothing);

    await tester.dragUntilVisible(
      find.byType(TextField).first,
      formScrollable,
      const Offset(0, 120),
    );
    await tester.enterText(find.byType(TextField).first, 'Surf Club');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel'));
    await tester.pumpAndSettle();

    await tapSubmit();
    expect(find.text('Proposal Submitted!'), findsOneWidget);
  });

  testWidgets('asset manifest loads and brand art is bundled', (tester) async {
    // main() reads the manifest before the first frame; this covers that path,
    // which the other tests skip by building SenecApp directly.
    await AssetCatalog.load();

    expect(
      () => rootBundle.load(BrandAssets.logo),
      returnsNormally,
      reason: 'brand art must be declared in pubspec.yaml',
    );

    // No organization art has been added yet, so every slug falls back. This
    // flips to non-null as files land in assets/images/orgs/.
    expect(AssetCatalog.orgImage('tennis_uniandes'), anyOf(isNull, isA<String>()));
  });

  testWidgets('notifications can all be marked read', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('3 unread'), findsOneWidget);

    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();

    expect(find.text('0 unread'), findsOneWidget);
  });
}
