import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_lock.g.dart';

/// How an unlock request ended.
enum UnlockResult {
  /// Biometrics or the credential of the device recognized the user.
  unlocked,

  /// The user closed the request of the system.
  cancelled,

  /// The device has no screen lock any more: it was removed while the app
  /// was in the background.
  noCredentials,

  /// Anything else: timeout, request stopped by the system, too many
  /// attempts, an error of the platform.
  failed,
}

/// The screen lock of the device (`docs/spec/accesso.md`, section 2): the
/// unlock (A1) and, from PR 4.11, the notice of the hub ask it.
///
/// Every answer is read when needed, never kept.
abstract interface class DeviceLock {
  /// Whether the device has a secure screen lock (PIN, pattern or
  /// password). On Android biometrics exist only with one, so it is also
  /// whether the user can unlock at all. False when the check fails.
  Future<bool> isSecure();

  /// Asks the system for biometrics or the credential of the device.
  ///
  /// It never throws: failures are an [UnlockResult].
  Future<UnlockResult> unlock();
}

/// [DeviceLock] on `local_auth`.
///
/// On Android `isDeviceSupported()` is `KeyguardManager.isDeviceSecure` or
/// enrolled biometrics, which need a secure lock: the check of a secure
/// screen lock, with no channel of our own.
class LocalAuthDeviceLock implements DeviceLock {
  new([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  /// Title of the request of the system.
  static const title = 'Home-made';

  /// Description of the request of the system.
  static const reason = 'Sblocca per continuare';

  /// Button that closes the request. Android shows its own when the
  /// credential of the device is allowed, as here.
  static const cancelButton = 'Annulla';

  final LocalAuthentication _auth;

  @override
  Future<bool> isSecure() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object catch (error) {
      _log('check', error);
      return false;
    }
  }

  @override
  Future<UnlockResult> unlock() async {
    try {
      final unlocked = await _auth.authenticate(
        localizedReason: reason,
        authMessages: const [
          // No subtitle: an empty one keeps the default English hint away.
          AndroidAuthMessages(
            signInTitle: title,
            signInHint: '',
            cancelButton: cancelButton,
          ),
        ],
        // No confirmation after the face is recognized. The defaults of the
        // other options are the ones of the specification: biometrics, then
        // PIN, pattern or password (`biometricOnly: false`), and a request
        // that ends when the app leaves the screen
        // (`persistAcrossBackgrounding: false`).
        sensitiveTransaction: false,
      );
      return unlocked ? UnlockResult.unlocked : UnlockResult.failed;
    } on LocalAuthException catch (error) {
      _log('request', error);
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled => UnlockResult.cancelled,
        LocalAuthExceptionCode.noCredentialsSet => UnlockResult.noCredentials,
        _ => UnlockResult.failed,
      };
    } on Object catch (error) {
      _log('request', error);
      return UnlockResult.failed;
    }
  }

  /// Only the step and the code: never the kind of biometrics.
  static void _log(String step, Object error) =>
      developer.log('unlock $step failed: ${_code(error)}', name: 'unlock');

  static String _code(Object error) => switch (error) {
    LocalAuthException(:final code) => code.name,
    PlatformException(:final code) => code,
    _ => 'unknown',
  };
}

/// The screen lock of the device. Tests override it with a fake.
@Riverpod(keepAlive: true)
DeviceLock deviceLock(Ref ref) => LocalAuthDeviceLock();
