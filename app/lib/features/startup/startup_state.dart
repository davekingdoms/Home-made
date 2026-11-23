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

  /// No household: A7, or A10 with a pending invite. Turned on by PR 4.6.
  household,

  /// Location never asked on this device: A11. Turned on by PR 4.8.
  location,

  /// Reopening with a saved session: unlock (A1). Turned on by PR 4.4.
  unlock,

  /// Nothing left: the hub, or the screen asked for.
  hub,
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

/// The state of the startup gate: the first missing step and what its
/// screen needs to know.
@immutable
class StartupState {
  const new checking() : this._(StartupStep.checking);

  const new unavailable(RemoteFailure this.failure)
    : step = StartupStep.unavailable,
      arrival = null,
      noticeOnly = false,
      demo = false;

  const new signIn([SignInArrival this.arrival = SignInArrival.start])
    : step = StartupStep.signIn,
      failure = null,
      noticeOnly = false,
      demo = false;

  /// First access; [noticeOnly] when the profile is already there and only
  /// the version of the notice changed; [demo] when the profile A3 creates
  /// is of a demo account, as chosen in A2.
  const new welcome({required this.noticeOnly, this.demo = false})
    : step = StartupStep.welcome,
      failure = null,
      arrival = null;

  /// No household (A7, A10). Not produced before PR 4.6.
  const new household() : this._(StartupStep.household);

  /// Location never asked on this device (A11). Not produced before PR 4.8.
  const new location() : this._(StartupStep.location);

  /// Reopening with a saved session (A1). Not produced before PR 4.4.
  const new unlock() : this._(StartupStep.unlock);

  const new hub() : this._(StartupStep.hub);

  const new _(this.step)
    : failure = null,
      arrival = null,
      noticeOnly = false,
      demo = false;

  final StartupStep step;

  /// Why the state is [StartupStep.unavailable].
  final RemoteFailure? failure;

  /// How the user arrived at [StartupStep.signIn].
  final SignInArrival? arrival;

  /// Whether A3 shows the checkbox only.
  final bool noticeOnly;

  /// Whether A3 creates the profile of a demo account.
  final bool demo;

  /// Whether A2 says that the session expired.
  bool get sessionLost => arrival == SignInArrival.sessionLost;

  @override
  bool operator ==(Object other) =>
      other is StartupState &&
      other.step == step &&
      other.failure == failure &&
      other.arrival == arrival &&
      other.noticeOnly == noticeOnly &&
      other.demo == demo;

  @override
  int get hashCode => Object.hash(step, failure, arrival, noticeOnly, demo);

  @override
  String toString() => 'StartupState(${step.name})';
}
