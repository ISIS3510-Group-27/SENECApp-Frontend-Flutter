import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/testing.dart';
import 'package:senecapp/data/auth/dev_auth_service.dart';
import 'package:senecapp/features/auth/session_status_screens.dart';
import 'package:senecapp/features/auth/sign_in_screen.dart';
import 'package:senecapp/features/auth/verify_email_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a signed-out student lands on sign-in', (tester) async {
    await pumpApp(tester, testServices());

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('signing in loads the profile from the backend', (tester) async {
    final backend = FakeBackend();
    await pumpApp(tester, testServices(backend: backend.client));

    await tester.enterText(find.byType(TextField), 's.arango@uniandes.edu.co');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('SENECApp'), findsOneWidget);
    // The profile comes first; the app's lists only load once there is one.
    expect(backend.requests.first.url.path, '/api/v1/me');
    expect(backend.requestsTo('GET', '/me'), hasLength(1));
    expect(
      backend.requests.first.headers['Authorization'],
      'Bearer test-token',
    );

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Sofía Arango'), findsOneWidget);
    expect(find.text('Ingeniería de Sistemas'), findsOneWidget);
    expect(find.text('AI/ML'), findsOneWidget);
  });

  testWidgets('only university emails are sent to the backend', (tester) async {
    var calls = 0;
    final backend = MockClient((_) async {
      calls++;
      return jsonResponse(sofiaJson);
    });
    await pumpApp(tester, testServices(backend: backend));

    await tester.enterText(find.byType(TextField), 'sofia@gmail.com');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Use your @uniandes.edu.co email.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets("a backend refusal signs out and shows the backend's reason", (
    tester,
  ) async {
    final backend = fakeBackend(
      me: {'detail': 'Email address is not verified'},
      meStatus: 403,
    );
    await pumpApp(tester, testServices(backend: backend));

    await tester.tap(find.text('Use demo student'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Email address is not verified'), findsOneWidget);
  });

  testWidgets('a new account waits for email verification', (tester) async {
    final auth = FakeAuthService(
      requiresPassword: true,
      supportsRegistration: true,
    );
    await pumpApp(tester, testServices(auth: auth));

    await tester.tap(find.text('New to SENECApp? Create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'new.student@uniandes.edu.co',
    );
    await tester.enterText(find.byType(TextField).last, 'secret123');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    expect(auth.verificationEmailsSent, 1);

    // Not clicked yet: stays put and says why.
    await tester.tap(find.text("I've verified my email"));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    expect(find.textContaining("isn't verified yet"), findsOneWidget);

    auth.inboxLinkClicked = true;
    await tester.tap(find.text("I've verified my email"));
    await tester.pumpAndSettle();

    // A fresh token carries the new email_verified claim to the backend.
    expect(auth.forcedRefreshes, 1);
    expect(find.text('SENECApp'), findsOneWidget);
  });

  testWidgets('a backend outage can be retried', (tester) async {
    final backend = FakeBackend()..offline = true;
    await pumpApp(
      tester,
      testServices(auth: signedInAuth(), backend: backend.client),
    );

    expect(find.byType(ProfileLoadFailedScreen), findsOneWidget);

    backend.offline = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('SENECApp'), findsOneWidget);
  });

  testWidgets('signing out returns to sign-in', (tester) async {
    await pumpApp(tester, testServices(auth: signedInAuth()));

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    // Scroll to the end so the row clears the bottom navigation bar.
    await tester.fling(find.text('INTERESTS'), const Offset(0, -1000), 2000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  test('dev sign-in sends dev:<email> and remembers it', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = DevAuthService(await SharedPreferences.getInstance());

    expect(await auth.restore(), isNull);
    await auth.signIn(email: ' S.Arango@uniandes.edu.co ', password: '');
    expect(await auth.idToken(), 'dev:s.arango@uniandes.edu.co');

    final restarted = DevAuthService(await SharedPreferences.getInstance());
    expect((await restarted.restore())?.email, 's.arango@uniandes.edu.co');

    await restarted.signOut();
    expect(await restarted.idToken(), isNull);
  });
}
