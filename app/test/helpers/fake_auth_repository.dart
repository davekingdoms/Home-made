import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:homemade/features/auth/auth_repository.dart';

/// Invented account of the tests.
const anna = SessionUser(id: 'user-anna', name: 'Anna');

/// In-memory [AuthRepository]: no network and no Google account picker.
class FakeAuthRepository implements AuthRepository {
  new({
    bool signedIn = true,
    this.user = anna,
    this.signInResult = SignInResult.signedIn,
  }) : _hasSession = ValueNotifier(signedIn);

  /// The account of the session, while there is one.
  SessionUser user;

  /// What the next sign-in returns. [SignInResult.signedIn] also opens the
  /// session.
  SignInResult signInResult;

  /// When set, the sign-in waits for it to complete.
  Completer<void>? signInGate;

  /// Calls to [signOut].
  int signOuts = 0;

  final ValueNotifier<bool> _hasSession;

  @override
  ValueListenable<bool> get hasSession => _hasSession;

  @override
  SessionUser? get currentUser => _hasSession.value ? user : null;

  @override
  Future<SignInResult> signInWithGoogle() async {
    await signInGate?.future;
    if (signInResult == SignInResult.signedIn) _hasSession.value = true;
    return signInResult;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    _hasSession.value = false;
  }

  /// Ends the session without "Esci", as an expired or revoked session.
  void loseSession() => _hasSession.value = false;

  /// Opens a session for [account], as a sign-in elsewhere would.
  void openSession([SessionUser account = anna]) {
    user = account;
    _hasSession.value = true;
  }
}
