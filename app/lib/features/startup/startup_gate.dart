import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/core/storage/local_store.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/device_lock.dart';
import 'package:homemade/features/device/device_registry.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:homemade/features/startup/startup_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'startup_gate.g.dart';

/// The one place that decides the first step missing at startup
/// (`docs/spec/accesso.md`, section 1): session (A2), privacy notice (A3),
/// household (A7/A10), location (A11), then the hub; and whether the unlock
/// (A1) covers the app, above the steps (section 2).
///
/// It follows the session of [AuthRepository]; with a session it reads the
/// account from Supabase and saves it on the device for that account, so an
/// offline start uses the last state saved. The router reads only the step
/// of [value]; the app covers itself with A1 while [StartupState.locked].
///
/// The lock comes at a cold start with a saved session and when the app
/// returns to the hub after [lockAfter] hidden; never with the sign-in
/// itself, during a request to unlock, or on a device without a secure
/// screen lock. The clock is monotonic, never the time of the system.
class StartupGate extends ChangeNotifier
    implements ValueListenable<StartupState> {
  new({
    required this._auth,
    required this._accounts,
    required this._store,
    required this._devices,
    required this._lock,
    DateTime Function()? now,
    Duration Function()? clock,
  }) : _now = now ?? DateTime.now,
       _clock = clock ?? _stopwatch() {
    _auth.hasSession.addListener(_onSessionChanged);
    _starting = true;
    _onSessionChanged();
    _starting = false;
  }

  /// Time hidden after which the app locks again on its return: one minute,
  /// with no setting.
  static const lockAfter = Duration(minutes: 1);

  /// Longest wait for the state of the account: then the start goes on with
  /// the state saved on the device.
  static const readTimeout = Duration(seconds: 8);

  /// Key of the saved state of the account [userId] in the [LocalStore].
  static String storeKey(String userId) => 'startup.account.$userId';

  /// Key of the choice of "Modalità demo" (A2) in the [LocalStore]: a value
  /// of the device, kept until the profile of a new account uses it.
  static const demoChoiceKey = 'auth.demo';

  final AuthRepository _auth;
  final AccountRepository _accounts;
  final LocalStore _store;
  final DeviceRegistry _devices;
  final DeviceLock _lock;
  final DateTime Function() _now;

  /// Monotonic time, for the time hidden.
  final Duration Function() _clock;

  /// The first missing step, without the lock.
  StartupState _step = const StartupState.checking();

  /// Whether A1 covers the app.
  bool _locked = false;

  StartupState _state = const StartupState.checking();

  /// True while the constructor reads the session restored at startup.
  bool _starting = false;

  final _unlocking = ValueNotifier<bool>(false);

  /// Whether the app is hidden: between [handleHide] and [handleResume].
  bool _hidden = false;

  /// When the app was hidden, by the clock; null while it shows, and when it
  /// was hidden during a request to unlock, which hides it itself.
  Duration? _hiddenSince;

  /// Whether the request ended while the app was hidden, without the user
  /// closing it: the system stopped it when the app left the screen, so it
  /// starts again on the return.
  bool _askOnReturn = false;

  /// Account of the open session, null without one.
  String? _userId;

  /// Last state of the account, read or saved.
  AccountStatus? _status;

  /// Whether the profile A3 creates is of a demo account: the choice of A2,
  /// read for an account without a profile.
  bool _demoChosen = false;

  /// True while "Esci" runs: the session ends because the user asked.
  bool _signingOut = false;

  /// Grows at every session change and every read: an older read that
  /// completes late is ignored.
  int _generation = 0;

  @override
  StartupState get value => _state;

  /// Whether the request of the system is open: "Sblocca" waits for it.
  ValueListenable<bool> get unlocking => _unlocking;

  /// Whether the signed-in account is a demo account, as its profile says.
  bool get isDemo => _status?.isDemo ?? false;

  /// Display name of the profile of the signed-in account, for the greeting
  /// of A7; null when it is not known.
  String? get displayName => _status?.displayName;

  /// The choice of "Modalità demo" saved on this device (A2).
  Future<bool> demoChosen() async {
    try {
      return await _store.read(demoChoiceKey) != null;
    } on Object catch (error) {
      _log('read demo choice', error);
      return false;
    }
  }

  /// Saves the choice of "Modalità demo" (A2), or forgets it.
  Future<void> chooseDemo({required bool demo}) async {
    try {
      if (demo) {
        await _store.write(demoChoiceKey, 'true');
      } else {
        await _store.remove(demoChoiceKey);
      }
    } on Object catch (error) {
      _log('save demo choice', error);
    }
  }

  /// Reads the state of the account again, after it was unavailable.
  void retry() {
    final userId = _userId;
    if (userId == null) return;
    unawaited(_load(userId, ++_generation));
  }

  /// Saves the first access (A3) of the signed-in user, then moves to the
  /// next step. With [displayName] it creates or updates the profile too,
  /// as a demo account if A2 chose so, and the choice goes; without it, it
  /// saves only the version of the notice read.
  ///
  /// It throws when the save fails: A3 tells the user and stays.
  Future<void> saveFirstAccess({String? displayName, String? avatarUrl}) async {
    final userId = _userId;
    final status = _status;
    if (userId == null || status == null) return;
    final demo = displayName != null && _demoChosen;
    await _accounts.saveFirstAccess(
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      noticeVersion: privacyNoticeVersion,
      readAt: _now(),
      isDemo: demo,
    );
    if (userId != _userId) return;
    if (displayName != null) {
      _demoChosen = false;
      await chooseDemo(demo: false);
    }
    final saved = status.copyWith(
      hasProfile: status.hasProfile || displayName != null,
      noticeVersion: privacyNoticeVersion,
      isDemo: status.isDemo || demo,
      displayName: displayName,
    );
    _status = saved;
    await _save(userId, saved);
    _set(_stepFor(saved));
  }

  /// The signed-in account is now a member of a household (A8, "Crea"):
  /// the state says so, is saved on the device and the gate moves on to the
  /// next step, or to the screen asked for.
  ///
  /// With [reread], after `already_member` (a household made, or an invite
  /// used, on another device), the state is read again from Supabase. If
  /// the read fails the answer of the server stands: the account is a
  /// member. It never throws.
  Future<void> householdJoined({bool reread = false}) async {
    final userId = _userId;
    final status = _status;
    if (userId == null || status == null) return;
    var joined = status.copyWith(hasMember: true);
    if (reread) {
      try {
        joined = await _accounts.readStatus(userId).timeout(readTimeout);
      } on Object catch (error) {
        _log('read', error);
      }
    }
    if (userId != _userId) return;
    _status = joined;
    await _save(userId, joined);
    _set(_stepFor(joined));
  }

  /// "Esci": deletes the row of the device (without waiting long for the
  /// network), forgets the device id and the state of the account on this
  /// installation, then closes the session. It never throws.
  Future<void> signOut() async {
    final userId = _userId;
    _signingOut = true;
    try {
      await _devices.forget();
      if (userId != null) await _store.remove(storeKey(userId));
      await _auth.signOut();
    } finally {
      _signingOut = false;
    }
  }

  /// "Elimina account demo" (I2): deletes the account on the server, then
  /// leaves it as "Esci" does, and forgets every value of the device, so the
  /// first start runs again in full. The row of the device went with the
  /// account: only its local id goes here.
  ///
  /// It throws when the deletion fails: I2 tells the user and stays.
  Future<void> deleteDemoAccount() async {
    // Marked before the call: once the account is gone the client may close
    // the session by itself, and that is no lost session. A failure clears
    // the mark again, so a session lost later still says so.
    _signingOut = true;
    try {
      await _accounts.deleteDemoAccount();
      await _devices.forget(deleteRow: false);
      try {
        await _store.clear();
      } on Object catch (error) {
        _log('clear', error);
      }
      _demoChosen = false;
      await _auth.signOut();
    } finally {
      _signingOut = false;
    }
  }

  /// Asks the system to unlock, when A1 covers the app and no request is
  /// open. A1 calls it with "Sblocca"; the gate itself when A1 appears and
  /// when the app returns with A1 on screen.
  ///
  /// Unlocked, or no screen lock any more: A1 goes. Closed by the user, or
  /// any other failure: A1 stays, without a message (the system shows its
  /// own), and no request starts by itself until the next return.
  Future<void> unlock() async {
    if (!_locked || _unlocking.value) return;
    _unlocking.value = true;
    try {
      final result = await _lock.unlock();
      if (!_locked) return;
      switch (result) {
        case UnlockResult.unlocked:
        case UnlockResult.noCredentials:
          _setLocked(false);
        case UnlockResult.cancelled:
          break;
        case UnlockResult.failed:
          if (_hidden) _askOnReturn = true;
      }
    } finally {
      _unlocking.value = false;
    }
  }

  /// The app is hidden (another app, the home screen, the screen off). The
  /// changes that a request to unlock causes, such as the screen of the PIN,
  /// do not count.
  void handleHide() {
    _hidden = true;
    if (_unlocking.value) return;
    _hiddenSince = _clock();
  }

  /// The app is back in the foreground. After [lockAfter] hidden on the hub,
  /// on a device with a secure screen lock, A1 covers it; with A1 already
  /// on screen, the request of the system starts again.
  void handleResume() {
    final userId = _userId;
    if (userId != null) unawaited(_devices.sync(userId));
    final hiddenSince = _hiddenSince;
    final askAgain = _askOnReturn;
    _hidden = false;
    _hiddenSince = null;
    _askOnReturn = false;
    if (_unlocking.value) return;
    if (_locked) {
      if (hiddenSince != null || askAgain) unawaited(unlock());
      return;
    }
    if (hiddenSince == null || userId == null) return;
    if (_step.step != StartupStep.hub) return;
    if (_clock() - hiddenSince < lockAfter) return;
    unawaited(_lockIfSecure(_generation));
  }

  @override
  void dispose() {
    _auth.hasSession.removeListener(_onSessionChanged);
    _unlocking.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    final generation = ++_generation;
    final user = _auth.hasSession.value ? _auth.currentUser : null;
    if (user == null) {
      final hadSession = _userId != null;
      _userId = null;
      _status = null;
      _locked = false;
      if (_signingOut) {
        _set(const StartupState.signIn(SignInArrival.signedOut));
      } else if (hadSession) {
        _set(const StartupState.signIn(SignInArrival.sessionLost));
      } else {
        _set(const StartupState.signIn());
        unawaited(_checkLostSession(generation));
      }
      return;
    }
    if (user.id == _userId) return;
    _userId = user.id;
    // A sign-in of this run never locks; a session restored at startup does
    // after the check of the screen lock, in [_load].
    _locked = false;
    unawaited(_devices.sync(user.id));
    unawaited(_load(user.id, generation, restored: _starting));
  }

  /// Covers the app with A1 if the device has a secure screen lock and the
  /// session of [generation] is still open, then asks to unlock.
  Future<void> _lockIfSecure(int generation) async {
    if (!await _lock.isSecure()) return;
    if (generation != _generation || _userId == null || _locked) return;
    _setLocked(true);
    unawaited(unlock());
  }

  /// At a start without a session: a device id still saved means that the
  /// last session ended without "Esci", which deletes it.
  Future<void> _checkLostSession(int generation) async {
    final identity = await _devices.identity();
    if (identity == null || generation != _generation) return;
    _set(const StartupState.signIn(SignInArrival.sessionLost));
  }

  /// Reads the state of the account. For the session [restored] at startup
  /// the check of the screen lock runs alongside: A1 covers the app as soon
  /// as the device says it has one, and the first step shows only once the
  /// check is done, so that no other screen shows before A1.
  Future<void> _load(
    String userId,
    int generation, {
    bool restored = false,
  }) async {
    _set(const StartupState.checking());
    final lockCheck = restored
        ? _lockIfSecure(generation)
        : Future<void>.value();
    AccountStatus? status;
    var failure = RemoteFailure.connection;
    try {
      status = await _accounts.readStatus(userId).timeout(readTimeout);
    } on Object catch (error) {
      failure = RemoteFailure.of(error);
      _log('read', error);
    }
    if (status != null) {
      await _save(userId, status);
    } else {
      status = await _saved(userId);
    }
    final demo = await _demoFor(status);
    await lockCheck;
    if (generation != _generation) return;
    if (status == null) {
      _set(StartupState.unavailable(failure));
      return;
    }
    _status = status;
    _demoChosen = demo;
    _set(_stepFor(status));
  }

  /// Whether the choice of A2 applies to the account in [status]: only to a
  /// new one. With a profile already there the choice goes, without effect.
  Future<bool> _demoFor(AccountStatus? status) async {
    if (status == null) return false;
    if (status.hasProfile) {
      await chooseDemo(demo: false);
      return false;
    }
    return await demoChosen();
  }

  /// The first step missing for an account in [status].
  StartupState _stepFor(AccountStatus status) {
    if (!status.noticeRead) {
      return StartupState.welcome(
        noticeOnly: status.hasProfile,
        demo: !status.hasProfile && _demoChosen,
      );
    }
    if (!_householdDone(status)) return const StartupState.household();
    if (!_locationDone) return const StartupState.location();
    return const StartupState.hub();
  }

  /// Household (A7; A10 with a pending invite from PR 4.7): done once the
  /// account is an active member of a household.
  bool _householdDone(AccountStatus status) => status.hasMember;

  /// Location (A11), asked once per device: always done until PR 4.8 reads
  /// it from the [LocalStore].
  bool get _locationDone => true;

  Future<AccountStatus?> _saved(String userId) async {
    try {
      final saved = await _store.read(storeKey(userId));
      return saved == null ? null : AccountStatus.fromJson(jsonDecode(saved));
    } on Object catch (error) {
      _log('read saved', error);
      return null;
    }
  }

  Future<void> _save(String userId, AccountStatus status) async {
    try {
      await _store.write(storeKey(userId), jsonEncode(status.toJson()));
    } on Object catch (error) {
      _log('save', error);
    }
  }

  void _set(StartupState step) {
    _step = step;
    _publish();
  }

  void _setLocked(bool locked) {
    _locked = locked;
    _publish();
  }

  void _publish() {
    final state = _step.withLock(locked: _locked);
    if (state == _state) return;
    _state = state;
    notifyListeners();
  }

  /// A monotonic clock: the time since the gate was born.
  static Duration Function() _stopwatch() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  static void _log(String step, Object error) => developer.log(
    'startup $step failed: ${remoteErrorCode(error)}',
    name: 'startup',
  );
}

/// The startup gate of the app. It follows the app as it hides and comes
/// back to the foreground: the lock and the device registry need it.
@Riverpod(keepAlive: true)
StartupGate startupGate(Ref ref) {
  final gate = StartupGate(
    auth: ref.watch(authRepositoryProvider),
    accounts: ref.watch(accountRepositoryProvider),
    store: ref.watch(localStoreProvider),
    devices: ref.watch(deviceRegistryProvider),
    lock: ref.watch(deviceLockProvider),
    clock: ref.watch(monotonicClockProvider),
  );
  final lifecycle = AppLifecycleListener(
    onHide: gate.handleHide,
    onResume: gate.handleResume,
  );
  ref.onDispose(() {
    lifecycle.dispose();
    gate.dispose();
  });
  return gate;
}

/// Monotonic time since the app started, for the time spent hidden: never
/// the time of the system, which the user can change. Tests override it.
@Riverpod(keepAlive: true)
Duration Function() monotonicClock(Ref ref) {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}
