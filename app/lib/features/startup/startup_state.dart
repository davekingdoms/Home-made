import 'package:flutter/foundation.dart';
import 'package:homemade/core/remote/remote_failure.dart';

/// The first step the user still has to go through at startup, in the order
/// of `docs/spec/accesso.md`, section 1.
enum StartupStep {
  /// The state of the account is being read.
  checking,

  /// The state could not be read and none is saved on the device.
  unavailable,

  /// No session: sign-in (A2).
  signIn,

  /// The current privacy notice is not read: first access (A3).
  welcome,

  /// No household: A7, or A10 with a pending invite.
  household,

  /// The household was just created with "Crea" of A8: A9. Kept only in
  /// memory, so it can be skipped: a cold start never shows it.
  invite,

  /// Location never asked on this device: A11. Turned on by PR 4.8.
  location,

  /// Nothing left: the hub, or the screen asked for.
  hub,
}

/// Something the hub tells the user once, after a step of the startup.
enum StartupNotice {
  /// An invite link opened by an account already in a household: the
  /// invite is not kept (`docs/spec/accesso.md`, section 1).
  alreadyInHousehold,
}

/// How the user arrived at sign-in (A2).
enum SignInArrival {
  /// No session at startup, never had one on this installation.
  start,

  /// The session ended without "Esci": expired or revoked. A2 says so.
  sessionLost,

  /// The user chose "Esci". A2 says nothing and forgets the screen asked
  /// for.
  signedOut,
}

/// The state of the startup gate: the first missing step, what its screen
/// needs to know and whether the unlock (A1) covers the app.
@immutable
class StartupState {
  const new checking() : this._(StartupStep.checking);

  const new unavailable(RemoteFailure this.failure)
    : step = StartupStep.unavailable,
      arrival = null,
      noticeOnly = false,
      demo = false,
      joining = false,
      locked = false;

  const new signIn([SignInArrival this.arrival = SignInArrival.start])
    : step = StartupStep.signIn,
      failure = null,
      noticeOnly = false,
      demo = false,
      joining = false,
      locked = false;

  /// First access; [noticeOnly] when the profile is already there and only
  /// the version of the notice changed; [demo] when the profile A3 creates
  /// is of a demo account, as chosen in A2.
  const new welcome({required this.noticeOnly, this.demo = false})
    : step = StartupStep.welcome,
      failure = null,
      arrival = null,
      joining = false,
      locked = false;

  /// No household: A7, or A10 when [joining] with a pending invite.
  const new household({this.joining = false})
    : step = StartupStep.household,
      failure = null,
      arrival = null,
      noticeOnly = false,
      demo = false,
      locked = false;

  /// The household was just created: A9.
  const new invite() : this._(StartupStep.invite);

  /// Location never asked on this device (A11). Not produced before PR 4.8.
  const new location() : this._(StartupStep.location);

  const new hub() : this._(StartupStep.hub);

  const new _(this.step)
    : failure = null,
      arrival = null,
      noticeOnly = false,
      demo = false,
      joining = false,
      locked = false;

  const new _copy(
    this.step, {
    required this.failure,
    required this.arrival,
    required this.noticeOnly,
    required this.demo,
    required this.joining,
    required this.locked,
  });

  final StartupStep step;

  /// Why the state is [StartupStep.unavailable].
  final RemoteFailure? failure;

  /// How the user arrived at [StartupStep.signIn].
  final SignInArrival? arrival;

  /// Whether A3 shows the checkbox only.
  final bool noticeOnly;

  /// Whether A3 creates the profile of a demo account.
  final bool demo;

  /// Whether the household step opens A10, for a pending invite, in place
  /// of A7.
  final bool joining;

  /// Whether the unlock (A1) covers the app. It is not a step: the router
  /// never reads it, and the screen under A1 stays as it is.
  final bool locked;

  /// This state with the unlock [locked] or not.
  StartupState withLock({required bool locked}) => locked == this.locked
      ? this
      : StartupState._copy(
          step,
          failure: failure,
          arrival: arrival,
          noticeOnly: noticeOnly,
          demo: demo,
          joining: joining,
          locked: locked,
        );

  /// Whether A2 says that the session expired.
  bool get sessionLost => arrival == SignInArrival.sessionLost;

  @override
  bool operator ==(Object other) =>
      other is StartupState &&
      other.step == step &&
      other.failure == failure &&
      other.arrival == arrival &&
      other.noticeOnly == noticeOnly &&
      other.demo == demo &&
      other.joining == joining &&
      other.locked == locked;

  @override
  int get hashCode =>
      Object.hash(step, failure, arrival, noticeOnly, demo, joining, locked);

  @override
  String toString() =>
      'StartupState(${step.name}${joining ? ', joining' : ''}'
      '${locked ? ', locked' : ''})';
}
