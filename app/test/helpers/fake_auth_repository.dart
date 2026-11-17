import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:homemade/features/auth/auth_repository.dart';

/// In-memory [AuthRepository]: no network and no Google account picker.
class FakeAuthRepository implements AuthRepository {
  new({bool signedIn = true, this.signInResult = SignInResult.signedIn})
    : _hasSession = ValueNotifier(signedIn);

  /// What the next sign-in returns. [SignInResult.signedIn] also opens the
  /// session.
  SignInResult signInResult;

  /// When set, the sign-in waits for it to complete.
  Completer<void>? signInGate;

  final ValueNotifier<bool> _hasSession;

  @override
  ValueListenable<bool> get hasSession => _hasSession;

  @override
  Future<SignInResult> signInWithGoogle() async {
    await signInGate?.future;
    if (signInResult == SignInResult.signedIn) _hasSession.value = true;
    return signInResult;
  }

  @override
  Future<void> signOut() async {
    _hasSession.value = false;
  }
}
