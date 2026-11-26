import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/features/auth/delete_demo_account.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/welcome_screen.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/features/settings/account_screen.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

/// The configuration of the tests on `dev`.
const _devConfig = AppConfig(
  appEnv: 'dev',
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'placeholder',
  googleWebClientId: 'placeholder.apps.googleusercontent.com',
  pagesBaseUrl: 'https://example.pages.dev',
);

const _signInPath = '/sign-in';
const _accountPath = '/settings/account';

/// The checkbox of A2.
Finder get _demoBox => find.descendant(
  of: find.byType(SignInScreen),
  matching: find.byType(Checkbox),
);

/// The "Elimina account demo" button of I2.
Finder get _deleteButton =>
    find.widgetWithText(OutlinedButton, deleteDemoAccountLabel);

/// A store with the choice of A2 already saved.
MemoryLocalStore _storeWithChoice() =>
    MemoryLocalStore()..values[StartupGate.demoChoiceKey] = 'true';

bool _ticked(WidgetTester tester) =>
    tester.widget<Checkbox>(_demoBox).value ?? false;

/// Ticks the notice of A3 and taps "Continua".
Future<void> _continueWelcome(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  await tester.ensureVisible(find.text('Continua'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continua'));
  await tester.pumpAndSettle();
}

/// Taps "Elimina account demo", which asks to confirm.
Future<void> _tapDelete(WidgetTester tester) async {
  await tester.tap(_deleteButton);
  await tester.pumpAndSettle();
}

/// Taps "Elimina" in the dialog.
Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Elimina'));
  await tester.pumpAndSettle();
}

void main() {
  group('"Modalità demo" in sign-in (A2)', () {
    for (final appEnv in ['', 'test', 'prod', 'Dev', 'dev ']) {
      testWidgets('is not there with APP_ENV "$appEnv"', (tester) async {
        await pumpApp(
          tester,
          location: _signInPath,
          config: AppConfig(
            appEnv: appEnv,
            supabaseUrl: testConfig.supabaseUrl,
            supabasePublishableKey: testConfig.supabasePublishableKey,
            googleWebClientId: testConfig.googleWebClientId,
            pagesBaseUrl: testConfig.pagesBaseUrl,
          ),
          auth: FakeAuthRepository(signedIn: false),
        );

        expect(find.text(demoChoiceLabel), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
      });
    }

    testWidgets('is there with APP_ENV dev, under the button, unticked', (
      tester,
    ) async {
      await pumpApp(
        tester,
        location: _signInPath,
        config: _devConfig,
        auth: FakeAuthRepository(signedIn: false),
      );

      expect(find.text(demoChoiceLabel), findsOneWidget);
      expect(_ticked(tester), isFalse);
      expect(
        tester.getTopLeft(_demoBox).dy,
        greaterThan(tester.getBottomLeft(find.byType(FilledButton)).dy),
      );
    });

    testWidgets('saves the choice on the device, and forgets it', (
      tester,
    ) async {
      final store = MemoryLocalStore();
      await pumpApp(
        tester,
        location: _signInPath,
        config: _devConfig,
        auth: FakeAuthRepository(signedIn: false),
        store: store,
      );

      await tester.tap(find.text(demoChoiceLabel));
      await tester.pump();
      expect(_ticked(tester), isTrue);
      expect(store.values, containsPair(StartupGate.demoChoiceKey, 'true'));

      await tester.tap(_demoBox);
      await tester.pump();
      expect(_ticked(tester), isFalse);
      expect(store.values, isNot(contains(StartupGate.demoChoiceKey)));
    });

    testWidgets('shows the choice already saved', (tester) async {
      await pumpApp(
        tester,
        location: _signInPath,
        config: _devConfig,
        auth: FakeAuthRepository(signedIn: false),
        store: _storeWithChoice(),
      );

      expect(_ticked(tester), isTrue);
    });
  });

  group('first access (A3)', () {
    testWidgets('with the choice, says the account is demo and saves it', (
      tester,
    ) async {
      final accounts = FakeAccountRepository(status: newAccount);
      final store = _storeWithChoice();
      await pumpApp(
        tester,
        location: '/welcome',
        accounts: accounts,
        store: store,
      );

      // Under the helper text of the name, 4 below, in its style.
      expect(find.text(demoAccountNotice), findsOneWidget);
      final helper = tester.getRect(find.text(nameHelperText));
      final notice = tester.getRect(find.text(demoAccountNotice));
      expect(notice.top, helper.bottom + AppSpacing.xxs);
      expect(notice.left, helper.left);
      expect(
        tester
            .widget<RichText>(
              find.descendant(
                of: find.text(demoAccountNotice),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style,
        tester
            .widget<RichText>(
              find.descendant(
                of: find.text(nameHelperText),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style,
      );

      await _continueWelcome(tester);

      expect(accounts.saves.single.isDemo, isTrue);
      expect(store.values, isNot(contains(StartupGate.demoChoiceKey)));
      expect(find.text(screenByCode('A7').label), findsOneWidget);
    });

    testWidgets('without the choice, creates a real account', (tester) async {
      final accounts = FakeAccountRepository(status: newAccount);
      await pumpApp(tester, location: '/welcome', accounts: accounts);

      expect(find.text(demoAccountNotice), findsNothing);

      await _continueWelcome(tester);

      expect(accounts.saves.single.isDemo, isFalse);
    });

    testWidgets('with the profile already there, the choice goes unused', (
      tester,
    ) async {
      final accounts = FakeAccountRepository(status: oldNoticeAccount);
      final store = _storeWithChoice();
      await pumpApp(
        tester,
        location: '/welcome',
        accounts: accounts,
        store: store,
      );

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.text(demoAccountNotice), findsNothing);
      expect(store.values, isNot(contains(StartupGate.demoChoiceKey)));

      await _continueWelcome(tester);

      expect(accounts.saves.single.isDemo, isFalse);
    });

    testWidgets('with an account that skips A3, the choice goes unused', (
      tester,
    ) async {
      final store = _storeWithChoice();
      await pumpApp(tester, store: store);

      expect(find.byType(HubScreen), findsOneWidget);
      expect(store.values, isNot(contains(StartupGate.demoChoiceKey)));
    });
  });

  group('"Elimina account demo" in Account (I2)', () {
    testWidgets('is not there for a real account', (tester) async {
      await pumpApp(tester, location: _accountPath);

      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Esci'), findsOneWidget);
      expect(find.text(deleteDemoAccountLabel), findsNothing);
    });

    testWidgets('is under "Esci" for a demo account, in the error colour', (
      tester,
    ) async {
      await pumpApp(
        tester,
        location: _accountPath,
        accounts: FakeAccountRepository(status: demoAccount),
      );

      expect(_deleteButton, findsOneWidget);
      expect(
        tester.getTopLeft(_deleteButton).dy,
        greaterThan(
          tester.getBottomLeft(find.widgetWithText(OutlinedButton, 'Esci')).dy,
        ),
      );
      final button = tester.widget<OutlinedButton>(_deleteButton);
      final context = tester.element(_deleteButton);
      expect(
        button.style?.foregroundColor?.resolve({}),
        Theme.of(context).colorScheme.error,
      );
    });

    testWidgets('asks to confirm, and "Annulla" deletes nothing', (
      tester,
    ) async {
      final accounts = FakeAccountRepository(status: demoAccount);
      final auth = FakeAuthRepository();
      final router = await pumpApp(
        tester,
        location: _accountPath,
        auth: auth,
        accounts: accounts,
      );

      await _tapDelete(tester);
      expect(find.byType(DeleteDemoAccountDialog), findsOneWidget);
      expect(find.text("Eliminare l'account demo?"), findsOneWidget);
      expect(
        find.text(
          "Si cancellano l'account, le case rimaste senza altri membri e "
          'tutti i loro dati. Non si può annullare.',
        ),
        findsOneWidget,
      );
      final delete = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Elimina'),
      );
      expect(
        delete.style?.foregroundColor?.resolve({}),
        Theme.of(tester.element(find.byType(DeleteDemoAccountDialog)))
            .colorScheme
            .error,
      );

      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(find.byType(DeleteDemoAccountDialog), findsNothing);
      expect(accounts.deletions, 0);
      expect(auth.signOuts, 0);
      expect(router.location, _accountPath);
    });

    testWidgets(
      'deletes the account, empties the device and leads to sign-in in '
      'silence',
      (tester) async {
        final accounts = FakeAccountRepository(status: demoAccount);
        final auth = FakeAuthRepository();
        final devices = FakeDeviceRepository();
        final store = MemoryLocalStore();
        final router = await pumpApp(
          tester,
          location: _accountPath,
          config: _devConfig,
          auth: auth,
          accounts: accounts,
          devices: devices,
          store: store,
        );
        // Values of the device of the next iterations.
        store.values['device.location'] = 'asked';
        expect(store.values, isNotEmpty);

        await _tapDelete(tester);
        await _confirmDelete(tester);

        expect(accounts.deletions, 1);
        expect(store.values, isEmpty);
        expect(auth.signOuts, 1);
        // The row went with the account on the server: no deletion here.
        expect(devices.rows, hasLength(1));
        expect(router.location, _signInPath);
        expect(find.text(sessionLostMessage), findsNothing);
        expect(_ticked(tester), isFalse);
      },
    );

    testWidgets(
      'leads to sign-in in silence also when the client closes the session '
      'before the answer',
      (tester) async {
        final accounts = FakeAccountRepository(status: demoAccount)
          ..deleteGate = Completer<void>();
        final auth = FakeAuthRepository();
        final router = await pumpApp(
          tester,
          location: _accountPath,
          auth: auth,
          accounts: accounts,
        );

        await _tapDelete(tester);
        // The indicator of I2 turns while the deletion waits: no settling.
        await tester.tap(find.widgetWithText(TextButton, 'Elimina'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // The account is gone on the server: the client closes the session
        // by itself, before the answer arrives.
        auth.loseSession();
        await tester.pumpAndSettle();
        accounts.deleteGate!.complete();
        await tester.pumpAndSettle();

        expect(accounts.deletions, 1);
        expect(router.location, _signInPath);
        expect(find.text(sessionLostMessage), findsNothing);
      },
    );

    testWidgets('after a failure, a session lost later says so', (
      tester,
    ) async {
      final accounts = FakeAccountRepository(status: demoAccount)
        ..deleteError = serverError;
      final auth = FakeAuthRepository();
      final router = await pumpApp(
        tester,
        location: _accountPath,
        auth: auth,
        accounts: accounts,
      );

      await _tapDelete(tester);
      await _confirmDelete(tester);
      expect(
        find.widgetWithText(
          SnackBar,
          "Non è stato possibile eliminare l'account. Riprova.",
        ),
        findsOneWidget,
      );
      expect(router.location, _accountPath);

      auth.loseSession();
      await tester.pumpAndSettle();

      expect(router.location, _signInPath);
      expect(find.text(sessionLostMessage), findsOneWidget);
    });

    const errors = {
      'without a network': (
        offline,
        'Nessuna connessione. Controlla la rete e riprova.',
      ),
      'when Supabase refuses': (
        serverError,
        "Non è stato possibile eliminare l'account. Riprova.",
      ),
    };
    for (final MapEntry(key: name, value: (error, message)) in errors.entries) {
      testWidgets('says "$message" $name, and stays', (tester) async {
        final accounts = FakeAccountRepository(status: demoAccount)
          ..deleteError = error;
        final auth = FakeAuthRepository();
        final store = MemoryLocalStore();
        final router = await pumpApp(
          tester,
          location: _accountPath,
          auth: auth,
          accounts: accounts,
          store: store,
        );
        final before = Map.of(store.values);

        await _tapDelete(tester);
        await _confirmDelete(tester);

        expect(find.widgetWithText(SnackBar, message), findsOneWidget);
        expect(router.location, _accountPath);
        expect(auth.signOuts, 0);
        expect(store.values, before);
        expect(
          tester.widget<OutlinedButton>(_deleteButton).onPressed,
          isNotNull,
        );
      });
    }
  });
}
