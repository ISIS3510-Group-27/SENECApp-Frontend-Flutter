import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:senecapp/app.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/api/client_context.dart';
import 'package:senecapp/data/auth/auth_service.dart';
import 'package:senecapp/data/location/location_service.dart';

import 'fake_backend.dart';

export 'fake_backend.dart';

/// An [AuthService] that keeps everything in memory.
class FakeAuthService implements AuthService {
  FakeAuthService({
    AuthAccount? account,
    this.requiresPassword = false,
    this.supportsRegistration = false,
    this.verifyOnRegister = false,
  }) : _account = account;

  AuthAccount? _account;

  @override
  final bool requiresPassword;

  @override
  final bool supportsRegistration;

  /// Whether new accounts come back already verified.
  final bool verifyOnRegister;

  /// Flipped by a test to simulate the link being clicked in the inbox.
  bool inboxLinkClicked = false;

  int forcedRefreshes = 0;
  int verificationEmailsSent = 0;

  @override
  Future<AuthAccount?> restore() async => _account;

  @override
  Future<AuthAccount> signIn({
    required String email,
    required String password,
  }) async => _account = AuthAccount(email: email.trim(), emailVerified: true);

  @override
  Future<AuthAccount> register({
    required String email,
    required String password,
  }) async {
    verificationEmailsSent++;
    return _account = AuthAccount(
      email: email.trim(),
      emailVerified: verifyOnRegister,
    );
  }

  @override
  Future<void> sendEmailVerification() async => verificationEmailsSent++;

  @override
  Future<AuthAccount?> reload() async {
    final account = _account;
    if (account == null) return null;
    return _account = AuthAccount(
      email: account.email,
      emailVerified: account.emailVerified || inboxLinkClicked,
    );
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    if (_account == null) return null;
    if (forceRefresh) forcedRefreshes++;
    return forceRefresh ? 'fresh-token' : 'test-token';
  }

  @override
  Future<void> signOut() async => _account = null;
}

/// The device details tests send in the `X-*` headers.
ClientContext testClientContext() => ClientContext(
  appVersion: '1.0.0',
  platform: 'android',
  deviceModel: 'Google Pixel 8',
  osVersion: '14',
);

/// `GET /me` for the backend's seeded demo student.
const sofiaJson = {
  'id': 1,
  'email': 's.arango@uniandes.edu.co',
  'full_name': 'Sofía Arango',
  'program': 'Ingeniería de Sistemas',
  'semester': 6,
  'avatar_url': null,
  'location_opt_in': true,
  'notifications_opt_in': true,
  'interests': [
    {'id': 12, 'slug': 'ai-ml', 'name': 'AI/ML'},
    {'id': 1, 'slug': 'tennis', 'name': 'Tennis'},
  ],
  'created_at': '2026-03-06T17:00:00Z',
};

/// A JSON response, encoded the way the backend sends it (UTF-8).
http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// A [FakeBackend] whose `GET /me` answers [me] with [meStatus].
MockClient fakeBackend({Object me = sofiaJson, int meStatus = 200}) =>
    FakeBackend(me: me, meStatus: meStatus).client;

/// Services wired to [backend], a [FakeBackend] unless given.
AppServices testServices({
  FakeAuthService? auth,
  http.Client? backend,
  LocationService? location,
  FakeQrCamera? camera,
}) {
  final fakeAuth = auth ?? FakeAuthService();
  return AppServices(
    auth: fakeAuth,
    location: location ?? FakeLocationService(),
    qrCamera: (camera ?? FakeQrCamera()).build,
    api: ApiClient(
      baseUrl: 'http://test/api/v1',
      auth: fakeAuth,
      context: testClientContext(),
      httpClient: backend ?? fakeBackend(),
    ),
  );
}

/// A student who is already signed in when the app opens.
FakeAuthService signedInAuth() => FakeAuthService(
  account: const AuthAccount(
    email: 's.arango@uniandes.edu.co',
    emailVerified: true,
  ),
);

/// Pumps the app at phone size so PhoneFrame steps aside and layouts match
/// what a device would show.
Future<void> pumpApp(WidgetTester tester, AppServices services) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(SenecApp(services: services));
  await tester.pumpAndSettle();
}

/// GPS that answers [result] (by default: standing at Mario Laserna).
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.result = const LocationResult.found(4.6026, -74.0649),
  });

  LocationResult result;

  /// How many times the position was read.
  int reads = 0;

  final List<LocationProblem> settingsOpened = [];

  @override
  Future<LocationResult> current() async {
    reads++;
    return result;
  }

  @override
  Future<void> openSettings(LocationProblem problem) async =>
      settingsOpened.add(problem);
}

/// A camera that "sees" whatever a test passes to [scan].
class FakeQrCamera {
  ValueChanged<String>? _onCode;

  Widget build(BuildContext context, ValueChanged<String> onCode) {
    _onCode = onCode;
    return const ColoredBox(
      key: Key('fake-camera'),
      color: Colors.black,
      child: SizedBox.expand(),
    );
  }

  /// Whether the scanner is showing the camera right now.
  bool get showing =>
      find.byKey(const Key('fake-camera')).evaluate().isNotEmpty;

  void scan(String text) => _onCode!(text);
}
