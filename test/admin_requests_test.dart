import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:senecapp/data/models/rso.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> openTennis(WidgetTester tester, FakeBackend backend) async {
    await pumpApp(
      tester,
      testServices(auth: signedInAuth(), backend: backend.client),
    );
    // Tennis (1) is one of the student's groups, listed in My RSOs.
    await tester.tap(find.text('My RSOs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tennis Uniandes').last);
    await tester.pumpAndSettle();
  }

  testWidgets('a member asks to become admin and sees it pending', (
    tester,
  ) async {
    // Tennis (1) is one of the student's groups, but they don't lead it.
    final backend = FakeBackend();
    await openTennis(tester, backend);

    final requestButton = find.text('Request admin access');
    await tester.scrollUntilVisible(requestButton, 200);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(requestButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'I can coach');
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();

    final sent = backend.requests.lastWhere(
      (r) => r.url.path.endsWith('/admin-requests'),
    );
    expect(sent.method, 'POST');
    expect(jsonDecode(sent.body), {'note': 'I can coach'});
    expect(find.textContaining('Admin request sent'), findsOneWidget);
    expect(find.text('Request admin access'), findsNothing);
  });

  testWidgets('an admin approves a pending request', (tester) async {
    final backend = FakeBackend(
      adminOf: {1},
      adminRequests: {
        1: [FakeBackend.adminRequest(id: 7, groupId: 1, note: 'Pick me')],
      },
    );
    await openTennis(tester, backend);

    final requests = find.text('Admin requests (1)');
    await tester.scrollUntilVisible(requests, 200);
    // Clear the pinned "Joined" bar at the bottom of the page.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(requests);
    await tester.pumpAndSettle();

    expect(find.text('Mateo Rojas'), findsOneWidget);
    expect(find.text('"Pick me"'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(
      backend.requests.last.url.path,
      endsWith('/groups/1/admin-requests/7/approve'),
    );
    expect(find.text('No requests waiting.'), findsOneWidget);
  });

  test('admin request fields are read from the group profile', () {
    final rso = Rso.fromJson({
      ...FakeBackend.proposal(id: 9, name: 'Club', reviewStatus: 'approved'),
      'admin_request_status': 'pending',
      'pending_admin_requests': 3,
    });

    expect(rso.adminRequestPending, isTrue);
    expect(rso.pendingAdminRequests, 3);
  });
}
