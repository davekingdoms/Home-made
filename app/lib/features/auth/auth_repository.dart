import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_repository.g.dart';

/// Outcome of a sign-in attempt.
///
/// Failures carry no detail: nothing about the user or the tokens leaves the
/// repository.
enum SignInResult {
  /// A session is open.
  signedIn,

  /// The user closed the Google account picker.
  cancelled,

  /// The OAuth client or the signing certificate of the app is not the
  /// registered one, or Google returned no ID token.
  configurationError,

  /// Supabase could not be reached.
  networkError,

  /// Supabase refused the ID token.
  rejected,

  /// Any other failure.
  failed,
}

/// The signed-in user, as Google describes the account.
@immutable
class SessionUser {
  const new({required this.id, this.name, this.avatarUrl});

  /// Id of the account on Supabase.
  final String id;

  /// Name of the Google account, if any.
  final String? name;

  /// Address of the photo of the Google account, if any.
  final String? avatarUrl;
}

/// Session of the signed-in user: sign-in with Google, sign-out and whether
/// a session is open.
abstract interface class AuthRepository {
  /// Whether a session is open. The startup gate listens to it.
  ValueListenable<bool> get hasSession;

  /// The user of the open session; null without a session.
  SessionUser? get currentUser;

  /// Asks Google for an account and opens a session with it.
  ///
  /// It never throws: failures are a [SignInResult].
  Future<SignInResult> signInWithGoogle();

  /// Closes the session, on this device and with Google.
  ///
  /// It never throws, and the local session is gone when it completes.
  Future<void> signOut();
}

/// The repository of the app. `main` overrides it once Supabase and Google
/// sign-in are initialized; tests override it with a fake.
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) =>
    throw StateError('authRepositoryProvider must be overridden at startup');
