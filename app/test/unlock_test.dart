import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/app_logo.dart';
import 'package:homemade/features/auth/device_lock.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/unlock_screen.dart';
import 'package:homemade/features/auth/welcome_screen.dart';
import 'package:homemade/features/dev/component_catalog_screen.dart';
import 'package:homemade/features/dev/screen_index_screen.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/features/startup/startup_screen.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/text_scale.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/design_harness.dart';
import 'helpers/fake_auth_repository.dart';
import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

/// The app hidden for [duration], then back in the foreground, as Android
/// tells it.
Future<void> away(
  WidgetTester tester,
  FakeClock clock,
  Duration duration,
) async {
  tester.binding
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  clock.advance(duration);
  tester.binding
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

/// The calls of the app to the platform channel, such as
/// `SystemNavigator.pop`, until the end of the test.
List<String> recordPlatformCalls(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call.method);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

Finder get unlockScreen => find.byType(UnlockScreen);

void main() {
  usePhoneWindow();

  group('at a cold start with a saved session', () {
    testWidgets('A1 covers the startup screen while the state is read, then '
        'the step shows', (tester) async {
      final lock = FakeDeviceLock(secure: true);
      final accounts = FakeAccountRepository(status: oldNoticeAccount)
        ..readGate = Completer<void>();
      await pumpApp(tester, lock: lock, accounts: accounts);

      expect(unlockScreen, findsOneWidget);
      expect(find.byType(StartupScreen), findsOneWidget);
      expect(lock.requestOpen, isTrue);

      lock.answer(UnlockResult.unlocked);
      await tester.pumpAndSettle();
      expect(unlockScreen, findsNothing);
      expect(find.byType(StartupScreen), findsOneWidget);

      accounts.readGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('A1 shows at once, with no frame of the screen under it', (
      tester,
    ) async {
      final lock = FakeDeviceLock(secure: true);
      await pumpApp(tester, lock: lock);

      expect(unlockScreen, findsOneWidget);
      final opacity = tester.widget<FadeTransition>(
        find
            .ancestor(of: unlockScreen, matching: find.byType(FadeTransition))
            .first,
      );
      expect(opacity.opacity.value, 1);
    });

    testWidgets('a device without a screen lock never shows A1', (
      tester,
    ) async {
      final lock = FakeDeviceLock();
      final clock = FakeClock();
      await pumpApp(tester, lock: lock, clock: clock);
      expect(find.byType(HubScreen), findsOneWidget);
      expect(unlockScreen, findsNothing);

      await away(tester, clock, const Duration(minutes: 2));
      expect(unlockScreen, findsNothing);
      expect(lock.requests, 0);
    });

    testWidgets('"Sblocca" asks again after a cancel, and waits for the '
        'request', (tester) async {
      final lock = FakeDeviceLock(secure: true);
      await pumpApp(tester, lock: lock);
      lock.answer(UnlockResult.cancelled);
      await tester.pumpAndSettle();
      expect(unlockScreen, findsOneWidget);
      expect(lock.requests, 1);

      await tester.tap(find.text(unlockLabel));
      await tester.pump();
      expect(lock.requests, 2);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(unlockLabel),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      expect(button.onPressed, isNull);

      lock.answer(UnlockResult.unlocked);
      await tester.pumpAndSettle();
      expect(unlockScreen, findsNothing);
      expect(find.byType(HubScreen), findsOneWidget);
    });
  });

  group('back after a minute', () {
    /// The app unlocked on Conti, with the detail of an account (H2) open.
    Future<void> openAccountDetail(
      WidgetTester tester,
      FakeDeviceLock lock,
      FakeClock clock,
    ) async {
      await pumpApp(tester, lock: lock, clock: clock);
      lock.answer(UnlockResult.unlocked);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finanze'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conti'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('open-H2-/finance/accounts/$exampleId')),
      );
      await tester.pumpAndSettle();
      expect(find.text('H2 · Dettaglio conto'), findsOneWidget);
    }

    testWidgets('A1 covers the stack, which comes back after the unlock', (
      tester,
    ) async {
      final lock = FakeDeviceLock(secure: true);
      final clock = FakeClock();
      await openAccountDetail(tester, lock, clock);

      await away(tester, clock, const Duration(minutes: 2));
      expect(unlockScreen, findsOneWidget);
      expect(lock.requestOpen, isTrue);

      lock.answer(UnlockResult.unlocked);
      await tester.pumpAndSettle();
      expect(unlockScreen, findsNothing);
      expect(find.text('H2 · Dettaglio conto'), findsOneWidget);

      await systemBack(tester);
      expect(find.text('H1 · I tuoi conti'), findsOneWidget);
    });

    testWidgets('after 30 seconds nothing covers the app', (tester) async {
      final lock = FakeDeviceLock(secure: true);
      final clock = FakeClock();
      await openAccountDetail(tester, lock, clock);

      await away(tester, clock, const Duration(seconds: 30));

      expect(unlockScreen, findsNothing);
      expect(lock.requests, 1);
    });

    testWidgets('the system back leaves the app and does not close H2', (
      tester,
    ) async {
      final lock = FakeDeviceLock(secure: true);
      final clock = FakeClock();
      await openAccountDetail(tester, lock, clock);
      await away(tester, clock, const Duration(minutes: 2));
      final calls = recordPlatformCalls(tester);

      await systemBack(tester);

      expect(calls, contains('SystemNavigator.pop'));
      expect(unlockScreen, findsOneWidget);
      lock.answer(UnlockResult.unlocked);
      await tester.pumpAndSettle();
      expect(find.text('H2 · Dettaglio conto'), findsOneWidget);
    });

    testWidgets('the system tells Android to handle the back gesture', (
      tester,
    ) async {
      final lock = FakeDeviceLock(secure: true);
      final clock = FakeClock();
      await openAccountDetail(tester, lock, clock);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      bool? handlesBack() =>
          calls
                  .lastWhere(
                    (call) =>
                        call.method ==
                        'SystemNavigator.setFrameworkHandlesBack',
                  )
                  .arguments
              as bool?;

      await away(tester, clock, const Duration(minutes: 2));
      expect(handlesBack(), isFalse);

      lock.answer(UnlockResult.unlocked);
      await tester.pumpAndSettle();
      expect(handlesBack(), isTrue);
    });

    testWidgets('the screen reader finds nothing under A1', (tester) async {
      final semantics = tester.ensureSemantics();
      final lock = FakeDeviceLock(secure: true);
      final clock = FakeClock();
      await openAccountDetail(tester, lock, clock);
      expect(find.semantics.byLabel('H2 · Dettaglio conto'), findsOneWidget);

      await away(tester, clock, const Duration(minutes: 2));

      expect(find.semantics.byLabel('H2 · Dettaglio conto'), findsNothing);
      expect(find.semantics.byLabel('Sblocca per continuare'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('no touch reaches the app under A1', (tester) async {
      final lock = FakeDeviceLock(secure: true);
      final clock = FakeClock();
      final router = await pumpApp(tester, lock: lock, clock: clock);
      lock.answer(UnlockResult.unlocked);
      await tester.pumpAndSettle();

      await away(tester, clock, const Duration(minutes: 2));
      await tester.tap(find.text('Finanze'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(router.location, '/');
      expect(unlockScreen, findsOneWidget);
    });

    testWidgets('the keyboard closes under A1', (tester) async {
      final lock = FakeDeviceLock(secure: true);
      final clock = FakeClock();
      await pumpApp(
        tester,
        location: '/dev/components',
        lock: lock,
        clock: clock,
      );
      lock.answer(UnlockResult.unlocked);
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Descrizione');
      await tester.scrollUntilVisible(
        field,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ComponentCatalogScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.showKeyboard(field);
      expect(tester.testTextInput.hasAnyClients, isTrue);

      await away(tester, clock, const Duration(minutes: 2));

      expect(tester.testTextInput.hasAnyClients, isFalse);
    });
  });

  group('"Esci dall\'account" on A1', () {
    testWidgets('confirms, then leads to sign-in without a message', (
      tester,
    ) async {
      final lock = FakeDeviceLock(secure: true);
      final auth = FakeAuthRepository();
      await pumpApp(tester, lock: lock, auth: auth);
      lock.answer(UnlockResult.cancelled);
      await tester.pumpAndSettle();

      await tester.tap(find.text(unlockSignOutLabel));
      await tester.pumpAndSettle();
      expect(find.text("Uscire dall'account?"), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Esci'));
      await tester.pumpAndSettle();

      expect(auth.signOuts, 1);
      expect(unlockScreen, findsNothing);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text(sessionLostMessage), findsNothing);
    });

    testWidgets('the system back closes the confirmation', (tester) async {
      final lock = FakeDeviceLock(secure: true);
      await pumpApp(tester, lock: lock);
      lock.answer(UnlockResult.cancelled);
      await tester.pumpAndSettle();
      await tester.tap(find.text(unlockSignOutLabel));
      await tester.pumpAndSettle();
      final calls = recordPlatformCalls(tester);

      await systemBack(tester);

      expect(find.text("Uscire dall'account?"), findsNothing);
      expect(unlockScreen, findsOneWidget);
      expect(calls, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('a new sign-in with Google opens the hub without A1', (
      tester,
    ) async {
      final lock = FakeDeviceLock(secure: true);
      await pumpApp(tester, lock: lock);
      lock.answer(UnlockResult.cancelled);
      await tester.pumpAndSettle();
      await tester.tap(find.text(unlockSignOutLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Esci'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continua con Google'));
      await tester.pumpAndSettle();

      expect(find.byType(HubScreen), findsOneWidget);
      expect(unlockScreen, findsNothing);
      expect(lock.requests, 1);
    });
  });

  testWidgets('a lost session leads from A1 to sign-in with the message', (
    tester,
  ) async {
    final lock = FakeDeviceLock(secure: true);
    final auth = FakeAuthRepository();
    await pumpApp(tester, lock: lock, auth: auth);
    expect(unlockScreen, findsOneWidget);

    auth.loseSession();
    await tester.pumpAndSettle();

    expect(unlockScreen, findsNothing);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text(sessionLostMessage), findsOneWidget);
  });

  group('the preview at /unlock', () {
    testWidgets('opens from the screen index and "Sblocca" leaves it', (
      tester,
    ) async {
      final router = await pumpApp(tester, location: screenIndexPath);
      final tile = find.byKey(const ValueKey('index-A1'));
      await tester.scrollUntilVisible(tile, 200);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(router.location, screenByCode('A1').path);
      expect(unlockScreen, findsOneWidget);

      // The index replaces the stack with A1: "Sblocca" opens the hub.
      await tester.tap(find.text(unlockLabel));
      await tester.pumpAndSettle();
      expect(router.location, '/');
      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('pushed on a screen, "Sblocca" goes back to it', (
      tester,
    ) async {
      final router = await pumpApp(tester, location: screenIndexPath);
      unawaited(router.push<void>(screenByCode('A1').path!));
      await tester.pumpAndSettle();
      expect(unlockScreen, findsOneWidget);

      await tester.tap(find.text(unlockLabel));
      await tester.pumpAndSettle();
      expect(find.byType(ScreenIndexScreen), findsOneWidget);
    });
  });

  group('A1 with the text at 200%', () {
    // The real font: the font of the tests draws every letter as a square,
    // much wider than Google Sans Flex.
    setUpAll(loadAppFonts);

    for (final window in const [Size(360, 640), Size(1280, 800)]) {
      testWidgets('fits ${window.width.toInt()} × ${window.height.toInt()}', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = AppTextScale.max;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final lock = FakeDeviceLock(secure: true);
        await pumpApp(tester, lock: lock, window: window);

        expect(tester.takeException(), isNull);
        expect(unlockScreen, findsOneWidget);
        final signOut = tester.getSize(
          find.ancestor(
            of: find.text(unlockSignOutLabel),
            matching: find.byWidgetPredicate(
              (widget) => widget is OutlinedButton,
            ),
          ),
        );
        final unlock = tester.getSize(
          find.ancestor(
            of: find.text(unlockLabel),
            matching: find.byWidgetPredicate(
              (widget) => widget is FilledButton,
            ),
          ),
        );
        expect(signOut.width, lessThan(unlock.width));
        expect(
          unlock.width,
          lessThanOrEqualTo(AppSizes.maxContentWidth),
          reason: 'the centred column',
        );
      });
    }
  });

  group('A1 at 390 × 844', () {
    setUpAll(loadAppFonts);

    /// [finder] inside A1, not in the hub under it.
    Finder inA1(Finder finder) =>
        find.descendant(of: unlockScreen, matching: finder);

    /// The visible pill of the button with [label]: its Material, without
    /// the touch target around it.
    Finder pill(String label) => find
        .descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          ),
          matching: find.byType(Material),
        )
        .first;

    testWidgets('keeps the measures of the specification', (tester) async {
      final lock = FakeDeviceLock(secure: true);
      await pumpApp(tester, lock: lock, window: const Size(390, 844));

      final logo = tester.getRect(inA1(find.byType(AppLogo)));
      expect(logo, const Rect.fromLTWH(151, 200, 88, 88));
      final title = tester.getRect(inA1(find.text('Home-made')));
      expect(title.top, 304);
      expect(title.height, 36);
      final subtitle = tester.getRect(
        inA1(find.text('Sblocca per continuare')),
      );
      expect(subtitle.top, 356);
      expect(subtitle.height, 22);

      final unlock = tester.getRect(pill(unlockLabel));
      expect(unlock, const Rect.fromLTRB(16, 712, 374, 768));
      final signOut = tester.getRect(pill(unlockSignOutLabel));
      expect(signOut.top, 776);
      expect(signOut.bottom, 820);
      expect(signOut.center.dx, 195);
      expect(signOut.width, lessThan(unlock.width));
    });
  });
}
