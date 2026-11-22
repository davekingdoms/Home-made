import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/nonce.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign-in with the Google account picker of the system, then on Supabase
/// with the ID token Google returns.
///
/// Only the default scopes are used (name, email, picture): no further
/// authorization and no access token.
class SupabaseAuthRepository implements AuthRepository {
  /// `googleSignIn` must already be initialized with the hash of
  /// `rawNonce`: use [start].
  new({
    required GoTrueClient auth,
    required this._googleSignIn,
    required this._rawNonce,
  }) : _auth = auth,
       _hasSession = ValueNotifier(auth.currentSession != null) {
    _authStateSubscription = auth.onAuthStateChange.listen(
      (state) => _hasSession.value = state.session != null,
      onError: (Object _) => _logFailure('supabase auth state', 'error'),
    );
  }

  final GoTrueClient _auth;
  final GoogleSignIn _googleSignIn;

  /// Raw nonce of this run of the app: Google received its hash.
  final String _rawNonce;

  final ValueNotifier<bool> _hasSession;
  late final StreamSubscription<AuthState> _authStateSubscription;

  /// Initializes Google sign-in and returns the repository.
  ///
  /// To be called once, at startup: Google sign-in is initialized once and
  /// before any other call. [serverClientId] is the web client ID, the
  /// audience Supabase expects in the ID token.
  static Future<SupabaseAuthRepository> start({
    required GoTrueClient auth,
    required GoogleSignIn googleSignIn,
    required String serverClientId,
  }) async {
    final rawNonce = generateRawNonce();
    await googleSignIn.initialize(
      serverClientId: serverClientId,
      nonce: hashNonce(rawNonce),
    );
    return SupabaseAuthRepository(
      auth: auth,
      googleSignIn: googleSignIn,
      rawNonce: rawNonce,
    );
  }

  @override
  ValueListenable<bool> get hasSession => _hasSession;

  @override
  SessionUser? get currentUser {
    final user = _auth.currentUser;
    if (_auth.currentSession == null || user == null) return null;
    return sessionUserFrom(user);
  }

  @override
  Future<SignInResult> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        _logFailure('google sign-in', 'no ID token');
        return SignInResult.configurationError;
      }
      await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        nonce: _rawNonce,
      );
      _hasSession.value = _auth.currentSession != null;
      return SignInResult.signedIn;
    } on GoogleSignInException catch (error) {
      _logFailure('google sign-in', error.code.name);
      return signInResultFromGoogle(error.code);
    } on AuthException catch (error) {
      _logFailure('supabase sign-in', _describe(error));
      return signInResultFromSupabase(error);
    } on Exception {
      _logFailure('sign-in', 'unexpected exception');
      return SignInResult.failed;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } on GoogleSignInException catch (error) {
      _logFailure('google sign-out', error.code.name);
    } on Exception {
      _logFailure('google sign-out', 'unexpected exception');
    }
    try {
      // The local session is removed before the server is told: it is gone
      // even when the request fails.
      await _auth.signOut();
    } on AuthException catch (error) {
      _logFailure('supabase sign-out', _describe(error));
    } on Exception {
      _logFailure('supabase sign-out', 'unexpected exception');
    }
    _hasSession.value = _auth.currentSession != null;
  }

  /// Stops listening to the session. The app keeps the repository for its
  /// whole life and never calls it.
  Future<void> dispose() async {
    await _authStateSubscription.cancel();
    _hasSession.dispose();
  }
}

/// The [SessionUser] of [user]: the name and the photo come from the Google
/// ID token, which Supabase copies into the metadata of the user.
SessionUser sessionUserFrom(User user) {
  final metadata = user.userMetadata ?? const <String, dynamic>{};
  String? text(String key) {
    final value = metadata[key];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  return SessionUser(
    id: user.id,
    name: text('full_name') ?? text('name'),
    avatarUrl: text('avatar_url') ?? text('picture'),
  );
}

/// The result for a failure of the Google account picker with [code].
SignInResult signInResultFromGoogle(GoogleSignInExceptionCode code) {
  if (code == GoogleSignInExceptionCode.canceled) return SignInResult.cancelled;
  if (code == GoogleSignInExceptionCode.clientConfigurationError ||
      code == GoogleSignInExceptionCode.providerConfigurationError) {
    return SignInResult.configurationError;
  }
  return SignInResult.failed;
}

/// The result for [error], thrown by Supabase for the ID token: the request
/// did not get an answer, or the answer is a refusal.
SignInResult signInResultFromSupabase(AuthException error) {
  if (error is AuthRetryableFetchException) return SignInResult.networkError;
  return SignInResult.rejected;
}

/// Kind, HTTP status and error code of [error]: never its message.
String _describe(AuthException error) {
  final kind = error is AuthRetryableFetchException ? 'no answer' : 'refused';
  return '$kind, status ${error.statusCode}, code ${error.code}';
}

/// Logs a failure with its kind and code only: never tokens, the nonce or
/// anything about the user.
void _logFailure(String step, String code) =>
    developer.log('$step failed: $code', name: 'auth');
