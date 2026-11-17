import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/dev/screen_index_screen.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/pump_app.dart';

const _signInPath = '/sign-in';
const _signInButton = 'Continua con Google';

void main() {
  group('session', () {
    final locations = [
      for (final entry in screenCatalog) ...entry.exampleLocations.keys,
      screenIndexPath,
    ];

    for (final location in locations) {
      testWidgets('without one, $location leads to sign-in', (tester) async {
        final router = await pumpApp(
          tester,
          location: location,
          auth: FakeAuthRepository(signedIn: false),
        );

        expect(router.location, _signInPath);
        expect(find.byType(SignInScreen), findsOneWidget);
      });
    }

    testWidgets('with one, sign-in leads to the hub', (tester) async {
      final router = await pumpApp(tester, location: _signInPath);

      expect(router.location, '/');
      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('when it ends, the open screen gives way to sign-in', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      final router = await pumpApp(
        tester,
        location: '/finance/transactions',
        auth: auth,
      );
      expect(router.location, '/finance/transactions');

      await auth.signOut();
      await tester.pumpAndSettle();

      expect(router.location, _signInPath);
      expect(find.byType(SignInScreen), findsOneWidget);
    });
  });

  group('sign-in (A2)', () {
    testWidgets('shows its code, the title and the Google button', (
      tester,
    ) async {
      await pumpApp(
        tester,
        location: _signInPath,
        auth: FakeAuthRepository(signedIn: false),
      );

      expect(find.text('A2 · Accesso'), findsOneWidget);
      expect(find.text('Home-made'), findsOneWidget);
      expect(find.text(_signInButton), findsOneWidget);
    });

    testWidgets('leads to the hub when it succeeds', (tester) async {
      final router = await pumpApp(
        tester,
        location: _signInPath,
        auth: FakeAuthRepository(signedIn: false),
      );

      await tester.tap(find.text(_signInButton));
      await tester.pumpAndSettle();

      expect(router.location, '/');
      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('shows an indicator while it waits', (tester) async {
      final gate = Completer<void>();
      final auth = FakeAuthRepository(signedIn: false)..signInGate = gate;
      await pumpApp(tester, location: _signInPath, auth: auth);

      await tester.tap(find.text(_signInButton));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_signInButton), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('says so when the user cancels', (tester) async {
      final router = await pumpApp(
        tester,
        location: _signInPath,
        auth: FakeAuthRepository(
          signedIn: false,
          signInResult: SignInResult.cancelled,
        ),
      );

      await tester.tap(find.text(_signInButton));
      await tester.pumpAndSettle();

      expect(find.text('Accesso annullato'), findsOneWidget);
      expect(router.location, _signInPath);
      // The button is back, ready for another attempt.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    const failures = [
      SignInResult.configurationError,
      SignInResult.networkError,
      SignInResult.rejected,
      SignInResult.failed,
    ];
    for (final failure in failures) {
      testWidgets('asks to retry after ${failure.name}', (tester) async {
        final router = await pumpApp(
          tester,
          location: _signInPath,
          auth: FakeAuthRepository(signedIn: false, signInResult: failure),
        );

        await tester.tap(find.text(_signInButton));
        await tester.pumpAndSettle();

        expect(find.text('Accesso non riuscito. Riprova.'), findsOneWidget);
        expect(find.text('Accesso annullato'), findsNothing);
        expect(router.location, _signInPath);
      });
    }
  });

  group('account (I2)', () {
    testWidgets('"Esci" closes the session and leads to sign-in', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      final router = await pumpApp(
        tester,
        location: '/settings/account',
        auth: auth,
      );
      expect(find.text('I2 · Account'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Esci'));
      await tester.pumpAndSettle();

      expect(auth.hasSession.value, isFalse);
      expect(router.location, _signInPath);
      expect(find.text('A2 · Accesso'), findsOneWidget);
    });
  });
}
