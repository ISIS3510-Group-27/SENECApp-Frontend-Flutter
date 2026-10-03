import 'package:flutter/foundation.dart';

/// The account the student is signed in with, as the sign-in provider sees it.
///
/// This is not the SENECApp profile: that comes from the backend's `GET /me`
/// once the account is known.
@immutable
class AuthAccount {
  const AuthAccount({required this.email, required this.emailVerified});

  final String email;

  /// The backend rejects unverified addresses, so an unverified account stops
  /// at the "check your inbox" screen.
  final bool emailVerified;
}

/// A sign-in failure with a message that can be shown to the student as is.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}

/// Signs the student in and hands out the token the backend expects in
/// `Authorization: Bearer <token>`.
///
/// Two implementations, picked by `AUTH_MODE`: [DevAuthService] for a local
/// backend, and [FirebaseAuthService] for real accounts.
abstract interface class AuthService {
  /// Whether new accounts can be created from the app. Dev accounts need no
  /// registration: any university email works.
  bool get supportsRegistration;

  /// Whether [AuthService.signIn] needs a password.
  bool get requiresPassword;

  bool get supportsMicrosoft;

  /// The account restored from the last run, or `null` when signed out.
  /// Called once at launch.
  Future<AuthAccount?> restore();

  Future<AuthAccount> signIn({required String email, required String password});

  Future<AuthAccount> signInWithMicrosoft();

  /// Creates the account and sends the verification email.
  Future<AuthAccount> register({
    required String email,
    required String password,
  });

  Future<void> sendEmailVerification();

  /// Re-reads the account, so a link clicked in the inbox is picked up.
  Future<AuthAccount?> reload();

  /// The bearer token for the backend, or `null` when signed out.
  ///
  /// [forceRefresh] fetches a new token even if the cached one has not
  /// expired, e.g. right after the email was verified, so the backend sees the
  /// new `email_verified` claim.
  Future<String?> idToken({bool forceRefresh = false});

  Future<void> signOut();
}
