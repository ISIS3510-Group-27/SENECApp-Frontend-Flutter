import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:senecapp/core/widgets/selectable_chip.dart';
import 'package:senecapp/data/models/rso.dart';
import 'package:senecapp/features/create_rso/create_rso_screen.dart';

import 'support/fakes.dart';

/// Proposing a group: it starts pending, visible only to its creator, until
/// Student Affairs approves it.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeBackend backend;

  Future<void> openApp(
    WidgetTester tester, {
    Map<int, Map<String, dynamic>> proposals = const {},
  }) async {
    backend = FakeBackend(
      proposals: proposals,
      memberIds: {1, 2, 5, ...proposals.keys},
    );
    await pumpApp(
      tester,
      testServices(auth: signedInAuth(), backend: backend.client),
    );
  }

  Finder formScrollable() => find
      .descendant(
        of: find.byType(CreateRsoScreen),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.dragUntilVisible(
      target,
      formScrollable(),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
  }

  /// Fills the form: [category] chip, then the fields (name, contact,
  /// description, in that order on screen).
  Future<void> fill(
    WidgetTester tester, {
    String name = 'Surf Club',
    String contact = '',
    String category = 'Travel',
    String description = 'Weekend surf trips to the Caribbean coast.',
  }) async {
    await tester.tap(find.text('New RSO'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), name);
    await tester.enterText(fields.at(1), contact);
    await scrollTo(tester, find.widgetWithText(SelectableChip, category));
    await tester.tap(find.widgetWithText(SelectableChip, category).first);
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, description);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await scrollTo(tester, find.text('Submit for Review'));
    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();
  }

  testWidgets('submits the proposal and shows it pending in My RSOs', (
    tester,
  ) async {
    await openApp(tester);
    await fill(tester, contact: 'surf@uniandes.edu.co');
    await submit(tester);

    final sent = backend.requestsTo('POST', '/groups').single;
    expect(jsonDecode(sent.body), {
      'name': 'Surf Club',
      'category': 'travel',
      'description': 'Weekend surf trips to the Caribbean coast.',
      'contact_email': 'surf@uniandes.edu.co',
    });
    expect(find.text('Proposal Submitted!'), findsOneWidget);
    expect(find.textContaining("we'll notify you"), findsOneWidget);

    await tester.tap(find.text('Back to Discover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My RSOs').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Surf Club'), 200);

    expect(find.text('Pending review'), findsOneWidget);
    expect(find.text('Waiting for Student Affairs'), findsOneWidget);
  });

  testWidgets('interests are optional, and only from the chosen category', (
    tester,
  ) async {
    await openApp(tester);
    await fill(tester, category: 'Business');

    // Business interests in the fixtures: Startups, Networking, Finance.
    expect(find.widgetWithText(SelectableChip, 'Startups'), findsOneWidget);
    expect(find.widgetWithText(SelectableChip, 'Tennis'), findsNothing);

    await scrollTo(tester, find.widgetWithText(SelectableChip, 'Finance'));
    await tester.tap(find.widgetWithText(SelectableChip, 'Finance'));
    await tester.tap(find.widgetWithText(SelectableChip, 'Startups'));
    await tester.pumpAndSettle();
    await submit(tester);

    final sent =
        jsonDecode(backend.requestsTo('POST', '/groups').single.body) as Map;
    expect(sent['tag_ids'], [7, 15]);
    expect(sent.containsKey('contact_email'), isFalse);
  });

  testWidgets('a bad email or short description keeps Submit off', (
    tester,
  ) async {
    await openApp(tester);
    await fill(tester, contact: 'not-an-email', description: 'Too short');

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('9/20 characters minimum'), findsOneWidget);

    await submit(tester);
    expect(backend.requestsTo('POST', '/groups'), isEmpty);
  });

  testWidgets("a taken name is the backend's to say, and the form stays", (
    tester,
  ) async {
    await openApp(tester);
    await fill(tester, name: 'tennis uniandes');
    await submit(tester);

    expect(find.text('A group with this name already exists'), findsOneWidget);
    expect(find.text('Proposal Submitted!'), findsNothing);
    expect(find.byType(CreateRsoScreen), findsOneWidget);
  });

  testWidgets('a pending group says so on its page, with no join button', (
    tester,
  ) async {
    await openApp(
      tester,
      proposals: {100: FakeBackend.proposal(id: 100, name: 'Surf Club')},
    );

    await tester.tap(find.text('My RSOs').last);
    await tester.pumpAndSettle();
    // Last in the list: scroll to the end so it clears the navigation bar.
    await tester.fling(
      find.text('MY ORGANIZATIONS'),
      const Offset(0, -1000),
      2000,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Surf Club'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pending review. Only you'), findsOneWidget);
    expect(find.text('Join RSO'), findsNothing);
    expect(find.text('✓ Joined - Welcome!'), findsNothing);
  });

  testWidgets('a rejected proposal shows the reason', (tester) async {
    await openApp(
      tester,
      proposals: {
        100: FakeBackend.proposal(
          id: 100,
          name: 'Surf Club',
          reviewStatus: 'rejected',
          rejectionReason: 'Viajeros Uniandes already covers trips.',
        ),
      },
    );

    await tester.tap(find.text('My RSOs').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Surf Club'), 200);

    expect(find.text('Not approved'), findsOneWidget);
    expect(
      find.text('Viajeros Uniandes already covers trips.'),
      findsOneWidget,
    );
  });

  test('reads the review status, approved when the backend omits it', () {
    final json = FakeBackend.proposal(
      id: 1,
      name: 'Surf Club',
      reviewStatus: 'rejected',
      rejectionReason: 'Duplicate',
    );
    final rso = Rso.fromJson(json);
    expect(rso.reviewStatus, ReviewStatus.rejected);
    expect(rso.rejectionReason, 'Duplicate');
    expect(rso.isApproved, isFalse);

    final older = Rso.fromJson({...json}..remove('review_status'));
    expect(older.isApproved, isTrue);
  });
}
