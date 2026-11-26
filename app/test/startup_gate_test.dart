import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/device_lock.dart';
import 'package:homemade/features/device/device_registry.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/features/startup/startup_state.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fakes.dart';

/// A second invented account.
const bruno = SessionUser(id: 'user-bruno', name: 'Bruno');

/// The gate with fakes around it.
class _Harness {
  new({
    bool signedIn = true,
    AccountStatus account = readyAccount,
    bool secure = false,
  }) : auth = FakeAuthRepository(signedIn: signedIn),
       accounts = FakeAccountRepository(status: account),
       lock = FakeDeviceLock(secure: secure);

  final FakeAuthRepository auth;
  final FakeAccountRepository accounts;
  final FakeDeviceLock lock;
  final devices = FakeDeviceRepository();
  final store = MemoryLocalStore();
  final clock = FakeClock();

  late final registry = DeviceRegistry(remote: devices, store: store);

  StartupGate start() {
    final gate = StartupGate(
      auth: auth,
      accounts: accounts,
      store: store,
      devices: registry,
      lock: lock,
      clock: clock.call,
    );
    addTearDown(gate.dispose);
    return gate;
  }

  /// Saves [status] as the last state read for Anna.
  void saveState(AccountStatus status) =>
      store.values[StartupGate.storeKey(anna.id)] = jsonEncode(status.toJson());

  /// The state saved for Anna, if any.
  AccountStatus? get savedState {
    final saved = store.values[StartupGate.storeKey(anna.id)];
    return saved == null ? null : AccountStatus.fromJson(jsonDecode(saved));
  }
}

/// Lets the reads of the fakes complete.
Future<void> flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('the first missing step', () {
    test('without a session is sign-in', () async {
      final gate = _Harness(signedIn: false).start();
      await flush();

      expect(gate.value, const StartupState.signIn());
      expect(gate.value.sessionLost, isFalse);
    });

    test('with a session is unknown until the account is read', () async {
      final harness = _Harness()..accounts.readGate = Completer<void>();
      final gate = harness.start();
      await flush();

      expect(gate.value, const StartupState.checking());

      harness.accounts.readGate!.complete();
      await flush();
      expect(gate.value, const StartupState.hub());
    });

    test('without user_settings is the whole first access', () async {
      final gate = _Harness(account: newAccount).start();
      await flush();

      expect(gate.value, const StartupState.welcome(noticeOnly: false));
    });

    test('with another version of the notice is the checkbox only', () async {
      final gate = _Harness(account: oldNoticeAccount).start();
      await flush();

      expect(gate.value, const StartupState.welcome(noticeOnly: true));
    });

    test('with every step done is the hub, and the state is saved', () async {
      final harness = _Harness();
      final gate = harness.start();
      await flush();

      expect(gate.value, const StartupState.hub());
      expect(harness.savedState, readyAccount);
    });

    test('without a household is still the hub until PR 4.6', () async {
      final gate = _Harness(
        account: const AccountStatus(
          hasProfile: true,
          noticeVersion: privacyNoticeVersion,
          hasMember: false,
        ),
      ).start();
      await flush();

      expect(gate.value, const StartupState.hub());
    });
  });

  group('offline', () {
    test('uses the state saved on the device', () async {
      final harness = _Harness()
        ..accounts.readError = offline
        ..saveState(readyAccount);
      final gate = harness.start();
      await flush();

      expect(gate.value, const StartupState.hub());
    });

    test('also when the saved state asks for the notice', () async {
      final harness = _Harness()
        ..accounts.readError = offline
        ..saveState(oldNoticeAccount);
      final gate = harness.start();
      await flush();

      expect(gate.value, const StartupState.welcome(noticeOnly: true));
    });

    test('without a saved state is unavailable, until a retry', () async {
      final harness = _Harness()..accounts.readError = offline;
      final gate = harness.start();
      await flush();

      expect(
        gate.value,
        const StartupState.unavailable(RemoteFailure.connection),
      );

      harness.accounts.readError = null;
      gate.retry();
      await flush();
      expect(gate.value, const StartupState.hub());
      expect(harness.accounts.reads, 2);
    });

    test('tells an error of Supabase apart from a missing network', () async {
      final harness = _Harness()..accounts.readError = serverError;
      final gate = harness.start();
      await flush();

      expect(gate.value, const StartupState.unavailable(RemoteFailure.server));
    });

    test('ignores the state saved for another account', () async {
      final harness = _Harness()..accounts.readError = offline;
      harness.store.values[StartupGate.storeKey(bruno.id)] = jsonEncode(
        readyAccount.toJson(),
      );
      final gate = harness.start();
      await flush();

      expect(gate.value.step, StartupStep.unavailable);
    });
  });

  group('a change of session while the app is open', () {
    test('a sign-in reads the account and registers the device', () async {
      final harness = _Harness(signedIn: false);
      final gate = harness.start();
      await flush();
      expect(gate.value.step, StartupStep.signIn);

      harness.auth.openSession();
      await flush();

      expect(gate.value, const StartupState.hub());
      expect(harness.devices.rows.values, [anna.id]);
    });

    test('a lost session leads to sign-in, saying so', () async {
      final harness = _Harness();
      final gate = harness.start();
      await flush();

      harness.auth.loseSession();
      await flush();

      expect(gate.value, const StartupState.signIn(SignInArrival.sessionLost));
      expect(gate.value.sessionLost, isTrue);
    });

    test(
      '"Esci" leads to sign-in, without saying the session expired',
      () async {
        final harness = _Harness();
        final gate = harness.start();
        await flush();

        await gate.signOut();
        await flush();

        expect(gate.value, const StartupState.signIn(SignInArrival.signedOut));
        expect(gate.value.sessionLost, isFalse);
      },
    );

    test('another account reads its own state', () async {
      final harness = _Harness();
      final gate = harness.start();
      await flush();
      harness.auth.loseSession();
      await flush();

      harness.accounts.status = newAccount;
      harness.auth.openSession(bruno);
      await flush();

      expect(gate.value, const StartupState.welcome(noticeOnly: false));
      expect(harness.store.values, contains(StartupGate.storeKey(bruno.id)));
    });

    test('a late read of a closed session is ignored', () async {
      final harness = _Harness()..accounts.readGate = Completer<void>();
      final gate = harness.start();
      await flush();

      harness.auth.loseSession();
      harness.accounts.readGate!.complete();
      await flush();

      expect(gate.value.step, StartupStep.signIn);
    });
  });

  group('a start without a session', () {
    test('after "Esci" says nothing', () async {
      final harness = _Harness();
      final first = harness.start();
      await flush();
      await first.signOut();

      // The app starts again.
      final gate = harness.start();
      await flush();

      expect(gate.value, const StartupState.signIn());
    });

    test('after a session lost while the app was closed says so', () async {
      final harness = _Harness(signedIn: false);
      // The device is still registered: the last session ended without
      // "Esci".
      await harness.registry.sync(anna.id);
      final gate = harness.start();
      await flush();

      expect(gate.value, const StartupState.signIn(SignInArrival.sessionLost));
    });
  });

  group('first access', () {
    test('saves the profile and the notice, then moves on', () async {
      final harness = _Harness(account: newAccount);
      final gate = harness.start();
      await flush();

      await gate.saveFirstAccess(displayName: 'Anna');

      expect(harness.accounts.saves.single, (
        userId: anna.id,
        displayName: 'Anna',
        avatarUrl: null,
        noticeVersion: privacyNoticeVersion,
        isDemo: false,
      ));
      expect(gate.value, const StartupState.hub());
      expect(harness.savedState?.noticeRead, isTrue);
      expect(harness.savedState?.hasProfile, isTrue);
    });

    test('with the checkbox only saves only the notice', () async {
      final harness = _Harness(account: oldNoticeAccount);
      final gate = harness.start();
      await flush();

      await gate.saveFirstAccess();

      expect(harness.accounts.saves.single.displayName, isNull);
      expect(gate.value, const StartupState.hub());
    });

    test('stays when the save fails', () async {
      final harness = _Harness(account: newAccount)
        ..accounts.saveError = offline;
      final gate = harness.start();
      await flush();

      await expectLater(
        gate.saveFirstAccess(displayName: 'Anna'),
        throwsA(offline),
      );
      expect(gate.value, const StartupState.welcome(noticeOnly: false));
    });
  });

  group('"Esci"', () {
    test('deletes the device and the saved state, then signs out', () async {
      final harness = _Harness();
      final gate = harness.start();
      await flush();
      expect(harness.devices.rows, hasLength(1));
      harness.store.values['device.location'] = 'kept';

      await gate.signOut();

      expect(harness.devices.rows, isEmpty);
      expect(harness.store.values, {'device.location': 'kept'});
      expect(harness.auth.signOuts, 1);
    });

    test('signs out also when the device cannot be deleted', () async {
      final harness = _Harness();
      final gate = harness.start();
      await flush();
      harness.devices.error = offline;

      await gate.signOut();

      expect(harness.store.values, isNot(contains(DeviceRegistry.storeKey)));
      expect(harness.auth.signOuts, 1);
      expect(gate.value.step, StartupStep.signIn);
    });

    test('keeps the choice of a demo account not yet used', () async {
      final harness = _Harness(account: newAccount);
      harness.store.values[StartupGate.demoChoiceKey] = 'true';
      final gate = harness.start();
      await flush();

      await gate.signOut();

      expect(harness.store.values, {StartupGate.demoChoiceKey: 'true'});
    });
  });

  group('demo accounts', () {
    test('the choice of A2 makes A3 create a demo profile', () async {
      final harness = _Harness(account: newAccount);
      final gate = harness.start();
      await gate.chooseDemo(demo: true);
      expect(await gate.demoChosen(), isTrue);
      harness.auth.loseSession();
      harness.auth.openSession();
      await flush();

      expect(
        gate.value,
        const StartupState.welcome(noticeOnly: false, demo: true),
      );

      await gate.saveFirstAccess(displayName: 'Anna');

      expect(harness.accounts.saves.single.isDemo, isTrue);
      expect(await gate.demoChosen(), isFalse);
      expect(gate.isDemo, isTrue);
      expect(harness.savedState?.isDemo, isTrue);
    });

    test('with a profile the choice goes, without effect', () async {
      final harness = _Harness(account: oldNoticeAccount);
      harness.store.values[StartupGate.demoChoiceKey] = 'true';
      final gate = harness.start();
      await flush();

      expect(gate.value, const StartupState.welcome(noticeOnly: true));
      expect(await gate.demoChosen(), isFalse);

      await gate.saveFirstAccess();
      expect(harness.accounts.saves.single.isDemo, isFalse);
      expect(gate.isDemo, isFalse);
    });

    test('the account says whether it is demo', () async {
      final gate = _Harness(account: demoAccount).start();
      await flush();

      expect(gate.isDemo, isTrue);
    });

    test('the deletion empties the device and signs out in silence', () async {
      final harness = _Harness(account: demoAccount);
      final gate = harness.start();
      await flush();
      harness.store.values['device.location'] = 'asked';

      await gate.deleteDemoAccount();
      await flush();

      expect(harness.accounts.deletions, 1);
      expect(harness.store.values, isEmpty);
      expect(harness.devices.rows, hasLength(1));
      expect(harness.auth.signOuts, 1);
      expect(gate.value, const StartupState.signIn(SignInArrival.signedOut));
    });

    test('a failed deletion changes nothing and throws', () async {
      final harness = _Harness(account: demoAccount)
        ..accounts.deleteError = offline;
      final gate = harness.start();
      await flush();
      final before = Map.of(harness.store.values);

      await expectLater(gate.deleteDemoAccount(), throwsA(offline));

      expect(harness.store.values, before);
      expect(harness.auth.signOuts, 0);
      expect(gate.value, const StartupState.hub());
    });

    test(
      'a session the client closes during the deletion is no lost session',
      () async {
        final harness = _Harness(account: demoAccount)
          ..accounts.deleteGate = Completer<void>();
        final gate = harness.start();
        await flush();

        final deletion = gate.deleteDemoAccount();
        await flush();
        // The account is gone on the server: the client closes the session
        // before the answer arrives.
        harness.auth.loseSession();
        await flush();
        expect(gate.value, const StartupState.signIn(SignInArrival.signedOut));

        harness.accounts.deleteGate!.complete();
        await deletion;
        await flush();

        expect(harness.accounts.deletions, 1);
        expect(harness.store.values, isEmpty);
        expect(gate.value, const StartupState.signIn(SignInArrival.signedOut));
        expect(gate.value.sessionLost, isFalse);
      },
    );

    test('after a failed deletion, a lost session says so', () async {
      final harness = _Harness(account: demoAccount)
        ..accounts.deleteError = serverError;
      final gate = harness.start();
      await flush();

      await expectLater(gate.deleteDemoAccount(), throwsA(serverError));
      expect(gate.value, const StartupState.hub());

      harness.auth.loseSession();
      await flush();

      expect(gate.value, const StartupState.signIn(SignInArrival.sessionLost));
    });
  });

  group('the saved state', () {
    test('keeps the flag of a demo account', () {
      expect(AccountStatus.fromJson(demoAccount.toJson()), demoAccount);
    });

    test('saved before the demo accounts reads as a real account', () {
      expect(
        AccountStatus.fromJson({
          'hasProfile': true,
          'noticeVersion': privacyNoticeVersion,
          'hasMember': true,
        }),
        readyAccount,
      );
    });
  });

  group('the lock', () {
    /// The app hidden for [duration], then back in the foreground.
    void away(_Harness harness, StartupGate gate, Duration duration) {
      gate.handleHide();
      harness.clock.advance(duration);
      gate.handleResume();
    }

    /// A gate on the hub, unlocked after its cold start.
    Future<StartupGate> unlockedOnHub(_Harness harness) async {
      final gate = harness.start();
      await flush();
      harness.lock.answer(UnlockResult.unlocked);
      await flush();
      expect(gate.value, const StartupState.hub());
      return gate;
    }

    test('covers a cold start with a session and asks to unlock', () async {
      final harness = _Harness(secure: true);
      final gate = harness.start();
      await flush();

      expect(gate.value, const StartupState.hub().withLock(locked: true));
      expect(harness.lock.requests, 1);
      expect(harness.lock.requestOpen, isTrue);
    });

    test('runs alongside the read of the account', () async {
      final harness = _Harness(secure: true, account: oldNoticeAccount)
        ..accounts.readGate = Completer<void>();
      final gate = harness.start();
      await flush();

      expect(gate.value, const StartupState.checking().withLock(locked: true));
      expect(harness.lock.requestOpen, isTrue);

      harness.lock.answer(UnlockResult.unlocked);
      await flush();
      expect(gate.value, const StartupState.checking());

      harness.accounts.readGate!.complete();
      await flush();
      expect(gate.value, const StartupState.welcome(noticeOnly: true));
    });

    test('shows no step before the check of the screen lock', () async {
      final harness = _Harness(secure: true)
        ..lock.checkGate = Completer<void>();
      final gate = harness.start();
      await flush();

      expect(harness.accounts.reads, 1);
      expect(gate.value, const StartupState.checking());

      harness.lock.checkGate!.complete();
      await flush();
      expect(gate.value, const StartupState.hub().withLock(locked: true));
    });

    test('never comes without a secure screen lock', () async {
      final harness = _Harness();
      final gate = harness.start();
      await flush();
      away(harness, gate, const Duration(minutes: 5));
      await flush();

      expect(gate.value, const StartupState.hub());
      expect(harness.lock.checks, 2);
      expect(harness.lock.requests, 0);
    });

    test('never comes with the sign-in of this run', () async {
      final harness = _Harness(signedIn: false, secure: true);
      final gate = harness.start();
      await flush();

      harness.auth.openSession();
      await flush();

      expect(gate.value, const StartupState.hub());
      expect(harness.lock.requests, 0);
    });

    test(
      'comes after a minute hidden on the hub, after a sign-in too',
      () async {
        final harness = _Harness(signedIn: false, secure: true);
        final gate = harness.start();
        await flush();
        harness.auth.openSession();
        await flush();

        away(harness, gate, const Duration(seconds: 59));
        await flush();
        expect(gate.value.locked, isFalse);

        away(harness, gate, StartupGate.lockAfter);
        await flush();
        expect(gate.value, const StartupState.hub().withLock(locked: true));
        expect(harness.lock.requests, 1);
      },
    );

    test('counts each time hidden on its own', () async {
      final harness = _Harness(secure: true);
      final gate = await unlockedOnHub(harness);

      away(harness, gate, const Duration(seconds: 30));
      away(harness, gate, const Duration(seconds: 30));
      await flush();

      expect(gate.value.locked, isFalse);
    });

    test('does not come on the steps before the hub', () async {
      final harness = _Harness(
        signedIn: false,
        secure: true,
        account: newAccount,
      );
      final gate = harness.start();
      await flush();
      harness.auth.openSession();
      await flush();
      expect(gate.value.step, StartupStep.welcome);

      away(harness, gate, const Duration(minutes: 5));
      await flush();

      expect(gate.value.locked, isFalse);
      expect(harness.lock.requests, 0);
    });

    test('does not come when the app was only inactive', () async {
      final harness = _Harness(secure: true);
      final gate = await unlockedOnHub(harness);

      harness.clock.advance(const Duration(minutes: 5));
      gate.handleResume();
      await flush();

      expect(gate.value.locked, isFalse);
    });

    test('ignores the changes of the app during a request', () async {
      final harness = _Harness(secure: true);
      final gate = harness.start();
      await flush();
      expect(harness.lock.requests, 1);

      // The screen of the PIN hides the app.
      away(harness, gate, const Duration(minutes: 2));
      await flush();
      expect(harness.lock.requests, 1);

      harness.lock.answer(UnlockResult.unlocked);
      await flush();
      expect(gate.value.locked, isFalse);

      gate.handleResume();
      await flush();
      expect(gate.value.locked, isFalse);
    });

    test('goes when the request succeeds', () async {
      final harness = _Harness(secure: true);
      final gate = harness.start();
      await flush();

      expect(gate.unlocking.value, isTrue);
      harness.lock.answer(UnlockResult.unlocked);
      await flush();

      expect(gate.value, const StartupState.hub());
      expect(gate.unlocking.value, isFalse);
    });

    test('opens one request at a time', () async {
      final harness = _Harness(secure: true);
      final gate = harness.start();
      await flush();

      unawaited(gate.unlock());
      await flush();

      expect(harness.lock.requests, 1);
    });

    test('stays when the user cancels, until the next return', () async {
      final harness = _Harness(secure: true);
      final gate = harness.start();
      await flush();

      harness.lock.answer(UnlockResult.cancelled);
      await flush();
      expect(gate.value.locked, isTrue);
      expect(gate.unlocking.value, isFalse);
      expect(harness.lock.requestOpen, isFalse);

      // The notification shade: no return from the background.
      gate.handleResume();
      await flush();
      expect(harness.lock.requests, 1);

      // "Sblocca".
      unawaited(gate.unlock());
      await flush();
      expect(harness.lock.requests, 2);
      harness.lock.answer(UnlockResult.cancelled);
      await flush();

      away(harness, gate, const Duration(seconds: 5));
      await flush();
      expect(harness.lock.requests, 3);
      expect(harness.lock.requestOpen, isTrue);
    });

    test('stays on any other failure, without a new request', () async {
      final harness = _Harness(secure: true);
      final gate = harness.start();
      await flush();

      harness.lock.answer(UnlockResult.failed);
      await flush();

      expect(gate.value.locked, isTrue);
      expect(harness.lock.requests, 1);
    });

    test('asks again on the return when the system stopped the request '
        'as the app left', () async {
      final harness = _Harness(secure: true);
      final gate = harness.start();
      await flush();

      gate.handleHide();
      harness.lock.answer(UnlockResult.failed);
      await flush();
      expect(harness.lock.requests, 1);

      gate.handleResume();
      await flush();
      expect(harness.lock.requests, 2);
    });

    test(
      'does not ask again after a cancel from the screen of the PIN',
      () async {
        final harness = _Harness(secure: true);
        final gate = harness.start();
        await flush();

        gate.handleHide();
        harness.lock.answer(UnlockResult.cancelled);
        await flush();
        gate.handleResume();
        await flush();

        expect(harness.lock.requests, 1);
        expect(gate.value.locked, isTrue);
      },
    );

    test('goes when the screen lock was removed', () async {
      final harness = _Harness(secure: true);
      final gate = harness.start();
      await flush();

      harness.lock.answer(UnlockResult.noCredentials);
      await flush();

      expect(gate.value, const StartupState.hub());
    });

    test('reads the screen lock at every return', () async {
      final harness = _Harness();
      final gate = harness.start();
      await flush();
      expect(gate.value.locked, isFalse);

      harness.lock.secure = true;
      away(harness, gate, const Duration(minutes: 2));
      await flush();
      expect(gate.value.locked, isTrue);
      harness.lock.answer(UnlockResult.unlocked);
      await flush();

      harness.lock.secure = false;
      away(harness, gate, const Duration(minutes: 2));
      await flush();
      expect(gate.value.locked, isFalse);
      expect(harness.lock.checks, 3);
    });

    test('goes with "Esci", to sign-in without a message', () async {
      final harness = _Harness(secure: true);
      final gate = harness.start();
      await flush();

      await gate.signOut();
      await flush();

      expect(gate.value, const StartupState.signIn(SignInArrival.signedOut));
    });

    test(
      'goes when the session is lost, to sign-in with the message',
      () async {
        final harness = _Harness(secure: true);
        final gate = harness.start();
        await flush();

        harness.auth.loseSession();
        await flush();
        expect(
          gate.value,
          const StartupState.signIn(SignInArrival.sessionLost),
        );

        // A request that ends later changes nothing.
        harness.lock.answer(UnlockResult.unlocked);
        await flush();
        expect(
          gate.value,
          const StartupState.signIn(SignInArrival.sessionLost),
        );
      },
    );
  });
}
