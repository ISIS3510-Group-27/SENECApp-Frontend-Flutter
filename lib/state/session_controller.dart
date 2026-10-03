import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../data/analytics/analytics.dart';
import '../data/api/api_client.dart';
import '../data/auth/auth_service.dart';
import '../data/models/student_profile.dart';
import '../data/repositories/me_repository.dart';
import 'push_registration.dart';

enum SessionStatus {
  /// Restoring the previous session at launch.
  starting,

  signedOut,

  /// Signed in, but the email link hasn't been clicked yet. The backend
  /// rejects unverified accounts, so the app waits here.
  unverified,

  /// Signed in, fetching the profile from `GET /me`.
  loadingProfile,

  /// Signed in, but the profile couldn't be loaded (offline, server down).
  profileFailed,

  signedIn,
}

/// Who is using the app, and how far through signing in they are.
///
/// The app shell switches screens on [status]: everything past sign-in only
/// exists while it is [SessionStatus.signedIn].
class SessionController extends ChangeNotifier {
  SessionController({
    required AuthService auth,
    required MeRepository me,
    required ApiClient api,
    Analytics? analytics,
    PushRegistration? push,
  }) : _auth = auth,
       _me = me,
       _analytics = analytics,
       _push = push {
    api.onUnauthorized = _onUnauthorized;
  }

  final AuthService _auth;
  final MeRepository _me;
  final Analytics? _analytics;
  final PushRegistration? _push;

  SessionStatus _status = SessionStatus.starting;
  AuthAccount? _account;
  StudentProfile? _student;
  String? _error;
  bool _busy = false;

  SessionStatus get status => _status;

  bool get supportsRegistration => _auth.supportsRegistration;

  bool get requiresPassword => _auth.requiresPassword;

  bool get supportsMicrosoft => _auth.supportsMicrosoft;

  /// The email being verified, for the "check your inbox" screen.
  String? get pendingEmail => _account?.email;

  /// Set once [status] is [SessionStatus.signedIn].
  StudentProfile? get student => _student;

  /// The last failure, worded for the student. Cleared by the next action.
  String? get error => _error;

  /// An action is in flight; buttons show a spinner and ignore taps.
  bool get busy => _busy;

  /// Restores the previous session. Call once at launch.
  Future<void> start() async {
    try {
      _account = await _auth.restore();
    } on Exception {
      _account = null;
    }
    await _continueWith(_account);
  }

  Future<void> signIn({required String email, required String password}) =>
      _run(() async {
        _validate(email, password);
        await _continueWith(
          await _auth.signIn(email: email, password: password),
        );
      });

  Future<void> register({required String email, required String password}) =>
      _run(() async {
        _validate(email, password, registering: true);
        await _continueWith(
          await _auth.register(email: email, password: password),
        );
      });

  Future<void> signInWithMicrosoft() =>
      _run(() async => _continueWith(await _auth.signInWithMicrosoft()));

  /// Sends the verification email again. Throws [AuthException] on failure.
  Future<void> resendVerification() => _auth.sendEmailVerification();

  /// Checks whether the link in the inbox has been clicked.
  Future<void> checkVerified() => _run(() async {
    final account = await _auth.reload();
    if (account != null && !account.emailVerified) {
      throw const AuthException(
        "Your email isn't verified yet. Open the link we sent you, then try "
        'again.',
      );
    }
    // The cached token still says "unverified"; the backend needs a new one.
    if (account != null) await _auth.idToken(forceRefresh: true);
    await _continueWith(account);
  });

  /// Tries `GET /me` again after [SessionStatus.profileFailed].
  Future<void> retry() => _loadProfile();

  Future<void> signOut({String? reason}) async {
    // Events still queued are sent with this student's token, so the next
    // account to sign in on this phone doesn't inherit them. Best effort.
    try {
      await _analytics?.flush().timeout(const Duration(seconds: 5));
    } on Object {
      // Kept for the next flush.
    }
    // Same for pushes: the next student on this phone mustn't get this one's.
    try {
      await _push?.unregister().timeout(const Duration(seconds: 5));
    } on Object {
      // The backend drops the token once FCM reports it dead.
    }
    await _auth.signOut();
    _account = null;
    _student = null;
    _error = reason;
    _setStatus(SessionStatus.signedOut);
  }

  Future<void> _continueWith(AuthAccount? account) async {
    _account = account;
    if (account == null) return _setStatus(SessionStatus.signedOut);
    if (!account.emailVerified) return _setStatus(SessionStatus.unverified);
    await _loadProfile();
  }

  Future<void> _loadProfile() async {
    _error = null;
    _setStatus(SessionStatus.loadingProfile);
    try {
      _student = await _me.fetch();
      _setStatus(SessionStatus.signedIn);
      // In the background: the app doesn't wait for push to be set up.
      unawaited(_push?.register());
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        // The backend turned the account away (not a university email, not
        // verified...). Its reason is the most useful thing to show.
        await signOut(reason: e.message);
      } else {
        _analytics?.error(e, screen: Screens.login);
        _error = e.message;
        _setStatus(SessionStatus.profileFailed);
      }
    }
  }

  void _onUnauthorized() {
    if (_status == SessionStatus.signedIn) {
      signOut(reason: 'Your session expired. Sign in again.');
    }
  }

  void _validate(String email, String password, {bool registering = false}) {
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(normalized)) {
      throw const AuthException('Enter your university email.');
    }
    if (!normalized.endsWith('@${AppConfig.allowedEmailDomain}')) {
      throw const AuthException(
        'Use your @${AppConfig.allowedEmailDomain} email.',
      );
    }
    if (_auth.requiresPassword && password.isEmpty) {
      throw const AuthException('Enter your password.');
    }
    if (registering && _auth.requiresPassword && password.length < 6) {
      throw const AuthException('Use a password with at least 6 characters.');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } on AuthException catch (e) {
      _error = e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _setStatus(SessionStatus status) {
    _status = status;
    notifyListeners();
  }
}
