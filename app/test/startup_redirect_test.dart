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
    });

    test('every other screen shows', () {
      for (final location in [
        '/',
        '/finance/transactions',
        '/settings/account',
        '/unlock',
        '/household/invite',
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
      ]) {
        final location = Uri(
          path: '/welcome',
          queryParameters: {'from': from},
        ).toString();
        expect(_redirect(state, location), '/', reason: from);
      }
    });

    test('the placeholders of the steps not on yet are destinations', () {
      expect(_redirect(state, '/start?from=%2Funlock'), '/unlock');
      expect(
        _redirect(state, '/start?from=%2Fhousehold%2Fjoin'),
        '/household/join',
      );
    });

    test('the query of the screen asked for comes back too', () {
      expect(
        _redirect(state, '/start?from=%2Fsettings%3Ftab%3D2'),
        '/settings?tab=2',
      );
    });
  });

  test('every step has the path of its screen', () {
    expect(startupStepPath(StartupStep.signIn), '/sign-in');
    expect(startupStepPath(StartupStep.welcome), '/welcome');
    expect(startupStepPath(StartupStep.household), '/household');
    expect(startupStepPath(StartupStep.location), '/location');
    expect(startupStepPath(StartupStep.unlock), '/unlock');
    expect(startupStepPath(StartupStep.hub), isNull);
  });
}
