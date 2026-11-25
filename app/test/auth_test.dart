import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/app_logo.dart';
import 'package:homemade/design/highlight_card.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/sign_out.dart';
import 'package:homemade/features/auth/welcome_screen.dart';
import 'package:homemade/features/dev/screen_index_screen.dart';
import 'package:homemade/features/device/device_registry.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/text_scale.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/design_harness.dart';
import 'helpers/fake_auth_repository.dart';
import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

const _signInPath = '/sign-in';
const String _signInButton = signInLabel;

/// The configuration of the tests on `dev`, with the checkbox of the demo
/// accounts.
const _devConfig = AppConfig(
  appEnv: 'dev',
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'placeholder',
  googleWebClientId: 'placeholder.apps.googleusercontent.com',
  pagesBaseUrl: 'https://example.pages.dev',
);

/// The notice of a lost session in A2: its box, around the text.
Finder get _sessionLostNotice => find
    .ancestor(
      of: find.text(sessionLostMessage),
      matching: find.byType(Container),
    )
    .first;

/// Pumps A2 after a lost session.
Future<void> _pumpSessionLost(
  WidgetTester tester, {
  AppConfig config = testConfig,
  Size? window,
}) async {
  final auth = FakeAuthRepository();
  await pumpApp(tester, auth: auth, config: config, window: window);
  auth.loseSession();
  await tester.pumpAndSettle();
  expect(find.byType(SignInScreen), findsOneWidget);
}

/// Every location of the app: the screens of the catalog and the index.
final List<String> _locations = [
  for (final entry in screenCatalog) ...entry.exampleLocations.keys,
  screenIndexPath,
];

/// Opens Account (I2) and taps "Esci", which asks to confirm.
Future<void> _tapEsci(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Esci'));
  await tester.pumpAndSettle();
}

void main() {
  group('without a session', () {
    for (final location in _locations) {
      testWidgets('$location leads to sign-in', (tester) async {
        final router = await pumpApp(
          tester,
          location: location,
          auth: FakeAuthRepository(signedIn: false),
        );

        expect(router.location, _signInPath);
        expect(find.byType(SignInScreen), findsOneWidget);
      });
    }

    testWidgets('after the sign-in, the screen asked for opens', (
      tester,
    ) async {
      final router = await pumpApp(
        tester,
        location: '/finance/transactions',
        auth: FakeAuthRepository(signedIn: false),
      );
      expect(router.location, _signInPath);

      await tester.tap(find.text(_signInButton));
      await tester.pumpAndSettle();

      expect(router.location, '/finance/transactions');
    });
  });

  group('with the privacy notice to read', () {
    for (final location in _locations) {
      testWidgets('$location leads to first access', (tester) async {
        final router = await pumpApp(
          tester,
          location: location,
          accounts: FakeAccountRepository(status: newAccount),
        );

        expect(router.location, '/welcome');
        expect(find.byType(WelcomeScreen), findsOneWidget);
      });
    }

    testWidgets('after first access, the screen asked for opens', (
      tester,
    ) async {
      final router = await pumpApp(
        tester,
        location: '/settings/appearance',
        accounts: FakeAccountRepository(status: newAccount),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      // "Continua" is at the bottom of the column, under the fold of the
      // window of the tests.
      await tester.ensureVisible(find.text('Continua'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continua'));
      await tester.pumpAndSettle();

      expect(router.location, '/settings/appearance');
    });
  });

  group('with a session', () {
    testWidgets('sign-in and first access lead to the hub', (tester) async {
      for (final location in [_signInPath, '/welcome', '/start']) {
        final router = await pumpApp(tester, location: location);

        expect(router.location, '/', reason: location);
        expect(find.byType(HubScreen), findsOneWidget);
      }
    });

    testWidgets('when it is lost, sign-in says so', (tester) async {
      final auth = FakeAuthRepository();
      final router = await pumpApp(
        tester,
        location: '/finance/transactions',
        auth: auth,
      );
      expect(router.location, '/finance/transactions');

      auth.loseSession();
      await tester.pumpAndSettle();

      expect(router.location, _signInPath);
      expect(find.text(sessionLostMessage), findsOneWidget);
      // A fixed notice above the button, not a snackbar.
      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester.getBottomLeft(_sessionLostNotice).dy,
        lessThan(tester.getTopLeft(find.byType(FilledButton)).dy),
      );

      // A new sign-in goes back where the user was.
      await tester.tap(find.text(_signInButton));
      await tester.pumpAndSettle();
      expect(router.location, '/finance/transactions');
    });
  });

  group('sign-in (A2)', () {
    testWidgets('shows the name of the app, the phrase and the button', (
      tester,
    ) async {
      await pumpApp(
        tester,
        location: _signInPath,
        auth: FakeAuthRepository(signedIn: false),
      );

      expect(find.text('Home-made'), findsOneWidget);
      expect(
        find.text('Conti, spese e conguagli di casa in un posto solo.'),
        findsOneWidget,
      );
      expect(find.text(_signInButton), findsOneWidget);
      expect(
        find.text('Accedi o registrati con il tuo account Google.'),
        findsOneWidget,
      );
      expect(find.text(sessionLostMessage), findsNothing);
      expect(find.text('Segnaposto'), findsNothing);
    });

    testWidgets('the card cannot be tapped and reads as one', (tester) async {
      final semantics = tester.ensureSemantics();
      final router = await pumpApp(
        tester,
        location: _signInPath,
        auth: FakeAuthRepository(signedIn: false),
      );
      final card = find.byType(HighlightCard);

      expect(tester.widget<HighlightCard>(card).onTap, isNull);
      expect(
        tester.getSemantics(card),
        matchesSemantics(
          label:
              'Home-made. Conti, spese e conguagli di casa in un posto solo.',
        ),
      );

      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(router.location, _signInPath);
      semantics.dispose();
    });

    testWidgets('the notice of a lost session reads as a status', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpSessionLost(tester);

      expect(
        tester.getSemantics(_sessionLostNotice),
        isSemantics(label: sessionLostMessage, isLiveRegion: true),
      );
      semantics.dispose();
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

    testWidgets('says nothing when the user cancels', (tester) async {
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

      expect(find.byType(SnackBar), findsNothing);
      expect(router.location, _signInPath);
      // The button is back, ready for another attempt.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    const messages = {
      SignInResult.networkError:
          'Nessuna connessione. Controlla la rete e riprova.',
      SignInResult.configurationError: 'Accesso non riuscito. Riprova.',
      SignInResult.rejected: 'Accesso non riuscito. Riprova.',
      SignInResult.failed: 'Accesso non riuscito. Riprova.',
    };
    for (final MapEntry(key: result, value: message) in messages.entries) {
      testWidgets('after ${result.name} says "$message"', (tester) async {
        final router = await pumpApp(
          tester,
          location: _signInPath,
          auth: FakeAuthRepository(signedIn: false, signInResult: result),
        );

        await tester.tap(find.text(_signInButton));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(SnackBar, message), findsOneWidget);
        expect(router.location, _signInPath);
      });
    }

    test('every result has its message, or none', () {
      for (final result in SignInResult.values) {
        final message = signInMessage(result);
        if (result == SignInResult.signedIn ||
            result == SignInResult.cancelled) {
          expect(message, isNull, reason: result.name);
        } else {
          expect(message, messages[result], reason: result.name);
        }
      }
    });
  });

  group('"Esci"', () {
    testWidgets('asks to confirm, and "Annulla" stays', (tester) async {
      final auth = FakeAuthRepository();
      final router = await pumpApp(
        tester,
        location: '/settings/account',
        auth: auth,
      );

      await _tapEsci(tester);
      expect(find.byType(SignOutDialog), findsOneWidget);
      expect(find.text("Uscire dall'account?"), findsOneWidget);
      expect(
        find.text('Per rientrare ti servirà il tuo account Google.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(find.byType(SignOutDialog), findsNothing);
      expect(auth.signOuts, 0);
      expect(router.location, '/settings/account');
    });

    testWidgets('deletes the device, then leads to sign-in in silence', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      final devices = FakeDeviceRepository();
      final store = MemoryLocalStore();
      final router = await pumpApp(
        tester,
        location: '/settings/account',
        auth: auth,
        devices: devices,
        store: store,
      );
      expect(devices.rows, hasLength(1));
      expect(store.values, contains(DeviceRegistry.storeKey));

      await _tapEsci(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Esci'));
      await tester.pumpAndSettle();

      expect(devices.rows, isEmpty);
      expect(store.values, isNot(contains(DeviceRegistry.storeKey)));
      expect(auth.signOuts, 1);
      expect(router.location, _signInPath);
      expect(find.text(sessionLostMessage), findsNothing);

      // The next sign-in opens the hub, not the screen left.
      await tester.tap(find.text(_signInButton));
      await tester.pumpAndSettle();
      expect(router.location, '/');
    });

    testWidgets('signs out also when the device cannot be deleted', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      final devices = FakeDeviceRepository();
      final store = MemoryLocalStore();
      final router = await pumpApp(
        tester,
        location: '/settings/account',
        auth: auth,
        devices: devices,
        store: store,
      );
      devices.error = offline;

      await _tapEsci(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Esci'));
      await tester.pumpAndSettle();

      expect(devices.rows, hasLength(1));
      expect(store.values, isNot(contains(DeviceRegistry.storeKey)));
      expect(auth.signOuts, 1);
      expect(router.location, _signInPath);
    });

    testWidgets('the "Esci" of the dialog is in the error colour', (
      tester,
    ) async {
      await pumpApp(tester, location: '/settings/account');
      await _tapEsci(tester);

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Esci'),
      );
      final context = tester.element(find.byType(SignOutDialog));
      expect(
        button.style?.foregroundColor?.resolve({}),
        Theme.of(context).colorScheme.error,
      );
    });
  });

  group('A2 at 390 × 844', () {
    // The real font: the font of the tests draws every letter as a square,
    // much wider than Google Sans Flex, and wraps the lines.
    setUpAll(loadAppFonts);

    const window = Size(390, 844);

    testWidgets('keeps the measures of the mockup', (tester) async {
      await pumpApp(
        tester,
        location: _signInPath,
        auth: FakeAuthRepository(signedIn: false),
        window: window,
      );

      expect(
        tester.getRect(find.byType(HighlightCard)),
        const Rect.fromLTRB(16, 16, 374, 476),
      );
      // At the bottom start of the card, 24 inside: the phrase on two lines.
      expect(
        tester.getRect(find.byType(AppLogo)),
        const Rect.fromLTWH(40, 260, 72, 72),
      );
      final title = tester.getRect(find.text('Home-made'));
      expect(title.left, 40);
      expect(title.top, 352);
      expect(title.height, 48);
      final phrase = tester.getRect(find.text(appPhrase));
      expect(phrase.left, 40);
      expect(phrase.top, 404);
      expect(phrase.bottom, 452);

      expect(
        tester.getRect(find.byType(FilledButton)),
        const Rect.fromLTRB(16, 734, 374, 790),
      );
      final caption = tester.getRect(find.text(signInCaption));
      expect(caption.top, 802);
      expect(caption.bottom, 820);
      expect(caption.center.dx, 195);
    });

    testWidgets('puts the notice of a lost session 12 above the button', (
      tester,
    ) async {
      await _pumpSessionLost(tester, window: window);

      expect(
        tester.getRect(find.byType(HighlightCard)),
        const Rect.fromLTRB(16, 16, 374, 476),
      );
      expect(
        tester.getRect(find.byType(FilledButton)),
        const Rect.fromLTRB(16, 734, 374, 790),
      );
      final notice = tester.getRect(_sessionLostNotice);
      expect(notice.left, 16);
      expect(notice.right, 374);
      expect(notice.bottom, 722);
      expect(notice.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
    });

    testWidgets('on dev, puts "Modalità demo" 8 under the line', (
      tester,
    ) async {
      await pumpApp(
        tester,
        location: _signInPath,
        config: _devConfig,
        auth: FakeAuthRepository(signedIn: false),
        window: window,
      );

      final box = tester.getRect(find.byType(Checkbox));
      expect(box.bottom, 820);
      expect(
        box.top - tester.getRect(find.text(signInCaption)).bottom,
        AppSpacing.xs,
      );
      expect(
        tester.getRect(find.byType(HighlightCard)),
        const Rect.fromLTRB(16, 16, 374, 476),
      );
    });
  });

  group('A2 with the text at 200%', () {
    setUpAll(loadAppFonts);

    for (final window in const [Size(360, 640), Size(1280, 800)]) {
      testWidgets('fits ${window.width.toInt()} × ${window.height.toInt()}', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = AppTextScale.max;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // The longest A2: the notice and the checkbox of the demo accounts.
        await _pumpSessionLost(tester, config: _devConfig, window: window);

        expect(tester.takeException(), isNull);
        final card = tester.getSize(find.byType(HighlightCard));
        expect(card.height, greaterThanOrEqualTo(SignInScreen.minCardHeight));
        expect(card.width, lessThanOrEqualTo(AppSizes.maxContentWidth));
        expect(
          tester.getBottomLeft(find.byType(HighlightCard)).dy,
          lessThan(tester.getTopLeft(_sessionLostNotice).dy),
        );
        expect(
          tester.getBottomLeft(_sessionLostNotice).dy,
          lessThan(tester.getTopLeft(find.byType(FilledButton)).dy),
        );

        // The column scrolls down to the checkbox.
        await tester.ensureVisible(find.text(demoChoiceLabel));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text(demoChoiceLabel)).bottom,
          lessThanOrEqualTo(window.height),
        );
      });
    }
  });
}
