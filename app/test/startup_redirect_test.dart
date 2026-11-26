import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/core/router/startup_redirect.dart';
import 'package:homemade/features/startup/startup_state.dart';

String? _redirect(StartupState state, String location) =>
    startupRedirect(state, Uri.parse(location));

void main() {
  group('while the state is not known', () {
    test('every screen waits on the startup screen', () {
      expect(
        _redirect(const StartupState.checking(), '/finance/transactions'),
        '/start?from=%2Ffinance%2Ftransactions',
      );
      expect(_redirect(const StartupState.checking(), '/'), '/start');
      expect(
        _redirect(
          const StartupState.unavailable(RemoteFailure.connection),
          '/settings',
        ),
        '/start?from=%2Fsettings',
      );
    });

    test('the startup screen stays', () {
      expect(_redirect(const StartupState.checking(), '/start'), isNull);
    });
  });

  group('without a session', () {
    const state = StartupState.signIn();

    test('every screen leads to sign-in, remembering where it was', () {
      expect(
        _redirect(state, '/finance/accounts/example'),
        '/sign-in?from=%2Ffinance%2Faccounts%2Fexample',
      );
      expect(_redirect(state, '/'), '/sign-in');
      expect(_redirect(state, '/sign-in'), isNull);
    });

    test('the startup screen hands on the screen asked for', () {
      expect(
        _redirect(state, '/start?from=%2Fsettings'),
        '/sign-in?from=%2Fsettings',
      );
    });

    test('after "Esci" the screen asked for is forgotten', () {
      expect(
        _redirect(
          const StartupState.signIn(SignInArrival.signedOut),
          '/settings/account',
        ),
        '/sign-in',
      );
    });

    test('a lost session keeps it', () {
      expect(
        _redirect(
          const StartupState.signIn(SignInArrival.sessionLost),
          '/finance/summary',
        ),
        '/sign-in?from=%2Ffinance%2Fsummary',
      );
    });
  });

  group('with the notice to read', () {
    const state = StartupState.welcome(noticeOnly: false);

    test('every screen leads to first access', () {
      expect(_redirect(state, '/settings'), '/welcome?from=%2Fsettings');
      expect(
        _redirect(state, '/sign-in?from=%2Fsettings'),
        '/welcome?from=%2Fsettings',
      );
      expect(_redirect(state, '/welcome'), isNull);
    });
  });

  group('without a household', () {
    const state = StartupState.household();

    test('every screen leads to A7, remembering where it was', () {
      expect(_redirect(state, '/settings'), '/household?from=%2Fsettings');
      expect(
        _redirect(state, '/welcome?from=%2Fsettings'),
        '/household?from=%2Fsettings',
      );
      expect(_redirect(state, '/'), '/household');
    });

    test('A7 and its sub-screens show, with the screen asked for', () {
      for (final location in [
        '/household',
        '/household/create',
        '/household/create?from=%2Fsettings',
        '/household/join',
        '/household/invite',
      ]) {
        expect(_redirect(state, location), isNull, reason: location);
      }
    });
  });

  group('with every step done', () {
    const state = StartupState.hub();

    test('the screens of the steps give way to the screen asked for', () {
      expect(
        _redirect(state, '/welcome?from=%2Ffinance%2Fsummary'),
        '/finance/summary',
      );
      expect(_redirect(state, '/start?from=%2Fsettings'), '/settings');
      expect(_redirect(state, '/sign-in'), '/');
      expect(_redirect(state, '/start'), '/');
      expect(
        _redirect(state, '/household/create?from=%2Fsettings%2Faccount'),
        '/settings/account',
      );
      for (final location in [
        '/household',
        '/household/create',
        '/household/invite',
        '/household/join',
      ]) {
        expect(_redirect(state, location), '/', reason: location);
      }
    });

    test('every other screen shows', () {
      for (final location in [
        '/',
        '/finance/transactions',
        '/settings/account',
        '/unlock',
        '/location',
      ]) {
        expect(_redirect(state, location), isNull, reason: location);
      }
    });

    test('a destination outside the app or of the gate is refused', () {
      for (final from in [
        'https://example.com/',
        '//example.com/',
        'settings',
        '/start',
        '/sign-in',
        '/welcome',
        '/household',
        '/household/join',
      ]) {
        final location = Uri(
          path: '/welcome',
          queryParameters: {'from': from},
        ).toString();
        expect(_redirect(state, location), '/', reason: from);
      }
    });

    test('the placeholders of the steps not on yet are destinations', () {
      expect(_redirect(state, '/start?from=%2Flocation'), '/location');
    });

    test('the query of the screen asked for comes back too', () {
      expect(
        _redirect(state, '/start?from=%2Fsettings%3Ftab%3D2'),
        '/settings?tab=2',
      );
    });
  });

  test('every step has the path of its screen', () {
    expect(startupStepPath(const StartupState.signIn()), '/sign-in');
    expect(
      startupStepPath(const StartupState.welcome(noticeOnly: false)),
      '/welcome',
    );
    expect(startupStepPath(const StartupState.household()), '/household');
    expect(
      startupStepPath(const StartupState.household(joining: true)),
      '/household/join',
    );
    expect(startupStepPath(const StartupState.invite()), '/household/invite');
    expect(startupStepPath(const StartupState.location()), '/location');
    expect(startupStepPath(const StartupState.hub()), isNull);
  });

  test('no step leads to the unlock (A1), which covers the app', () {
    for (final state in [
      const StartupState.checking(),
      const StartupState.unavailable(RemoteFailure.connection),
      const StartupState.signIn(),
      const StartupState.welcome(noticeOnly: false),
      const StartupState.household(),
      const StartupState.household(joining: true),
      const StartupState.invite(),
      const StartupState.location(),
      const StartupState.hub(),
    ]) {
      expect(startupStepPath(state), isNot('/unlock'), reason: '$state');
    }
    expect(_redirect(const StartupState.hub(), '/unlock'), isNull);
  });

  group('with a pending invite', () {
    const state = StartupState.household(joining: true);

    test('the household step opens A10 in place of A7', () {
      expect(_redirect(state, '/'), '/household/join');
      expect(_redirect(state, '/household'), '/household/join');
      expect(_redirect(state, '/household/create'), '/household/join');
      expect(_redirect(state, '/household/join'), isNull);
    });

    test('the screen asked for still travels along', () {
      expect(_redirect(state, '/settings'), '/household/join?from=%2Fsettings');
    });
  });

  group('after "Crea" of A8', () {
    const state = StartupState.invite();

    test('the step is A9', () {
      expect(_redirect(state, '/household/create'), '/household/invite');
      expect(_redirect(state, '/'), '/household/invite');
      expect(_redirect(state, '/household/invite'), isNull);
    });

    test('A9 gives way to the screen asked for once closed', () {
      expect(
        _redirect(
          const StartupState.hub(),
          '/household/invite?from=%2Fsettings',
        ),
        '/settings',
      );
      expect(_redirect(const StartupState.hub(), '/household/invite'), '/');
    });
  });

  test('the lock does not move the router', () {
    for (final state in [
      const StartupState.checking(),
      const StartupState.welcome(noticeOnly: true),
      const StartupState.hub(),
    ]) {
      for (final location in ['/', '/start', '/welcome', '/finance/summary']) {
        expect(
          _redirect(state.withLock(locked: true), location),
          _redirect(state, location),
          reason: '$state at $location',
        );
      }
    }
  });
}
