import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Local-development sign-in: the token is just `dev:<email>`.
///
/// The backend accepts it only while it runs with `AUTH_PROVIDER=dev`, which
/// is what lets the team work before the Firebase project exists. The email is
/// remembered between runs so hot restarts don't ask again.
class DevAuthService implements AuthService {
  DevAuthService(this._prefs);

  static const _emailKey = 'dev_auth.email';

  final SharedPreferences _prefs;
  String? _email;

  @override
  bool get supportsRegistration => false;

  @override
  bool get requiresPassword => false;

  @override
  Future<AuthAccount?> restore() async {
    _email = _prefs.getString(_emailKey);
    return _account;
  }

  @override
  Future<AuthAccount> signIn({
    required String email,
    required String password,
  }) async {
    _email = email.trim().toLowerCase();
    await _prefs.setString(_emailKey, _email!);
    return _account!;
  }

  @override
  Future<AuthAccount> register({
    required String email,
    required String password,
  }) => signIn(email: email, password: password);

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<AuthAccount?> reload() async => _account;

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      _email == null ? null : 'dev:$_email';

  @override
  Future<void> signOut() async {
    _email = null;
    await _prefs.remove(_emailKey);
  }

  // Dev tokens are trusted as verified by the backend.
  AuthAccount? get _account =>
      _email == null ? null : AuthAccount(email: _email!, emailVerified: true);
}
