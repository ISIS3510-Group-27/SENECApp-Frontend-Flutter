import 'package:firebase_auth/firebase_auth.dart';

import 'auth_service.dart';

/// Email-and-password accounts on Firebase Authentication.
///
/// Firebase keeps the session on the device and refreshes the hourly ID token
/// on its own; [idToken] always returns a valid one.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService([FirebaseAuth? auth])
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  bool get supportsRegistration => true;

  @override
  bool get requiresPassword => true;

  @override
  Future<AuthAccount?> restore() async {
    // currentUser is null until Firebase has read the persisted session; the
    // first auth-state event is the answer.
    final user = await _auth.authStateChanges().first;
    return _toAccount(user);
  }

  @override
  Future<AuthAccount> signIn({
    required String email,
    required String password,
  }) => _guard(() async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return _toAccount(credential.user)!;
  });

  @override
  Future<AuthAccount> register({
    required String email,
    required String password,
  }) => _guard(() async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user!.sendEmailVerification();
    return _toAccount(credential.user)!;
  });

  @override
  Future<void> sendEmailVerification() =>
      _guard(() async => _auth.currentUser?.sendEmailVerification());

  @override
  Future<AuthAccount?> reload() => _guard(() async {
    await _auth.currentUser?.reload();
    return _toAccount(_auth.currentUser);
  });

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      _auth.currentUser?.getIdToken(forceRefresh);

  @override
  Future<void> signOut() => _auth.signOut();

  AuthAccount? _toAccount(User? user) => user == null
      ? null
      : AuthAccount(email: user.email ?? '', emailVerified: user.emailVerified);

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e.code));
    }
  }

  static String _messageFor(String code) => switch (code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'Wrong email or password.',
    'invalid-email' => "That doesn't look like an email address.",
    'email-already-in-use' =>
      'There is already an account with this email. Sign in instead.',
    'weak-password' => 'Use a password with at least 6 characters.',
    'user-disabled' => 'This account has been disabled.',
    'too-many-requests' => 'Too many attempts. Wait a minute and try again.',
    'network-request-failed' => 'No connection. Check your internet.',
    _ => 'Sign-in failed ($code). Try again.',
  };
}
