import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/design/cookie.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/sign_out.dart';
import 'package:homemade/features/auth/welcome_screen.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

/// The "Continua" button.
FilledButton _continueButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

Future<void> _tick(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
}

Future<void> _tapContinue(WidgetTester tester) async {
  await tester.tap(find.text('Continua'));
  await tester.pumpAndSettle();
}

/// Pumps first access for an account in [status].
Future<FakeAccountRepository> _pumpWelcome(
  WidgetTester tester, {
  AccountStatus status = newAccount,
  SessionUser user = anna,
  List<Uri>? openedLinks,
}) async {
  final accounts = FakeAccountRepository(status: status);
  await pumpApp(
    tester,
    location: '/welcome',
    auth: FakeAuthRepository(user: user),
    accounts: accounts,
    openedLinks: openedLinks,
  );
  expect(find.byType(WelcomeScreen), findsOneWidget);
  return accounts;
}

void main() {
  group('the whole first access', () {
    testWidgets('shows the initial, the name from Google and the checkbox', (
      tester,
    ) async {
      await _pumpWelcome(tester);

      expect(find.byType(CookieAvatar), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Anna'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text("Ho letto l'informativa privacy"), findsOneWidget);
      expect(find.text('Continua'), findsOneWidget);
    });

    testWidgets('"Continua" waits for the checkbox', (tester) async {
      await _pumpWelcome(tester);
      expect(_continueButton(tester).onPressed, isNull);

      await _tick(tester);
      expect(_continueButton(tester).onPressed, isNotNull);
    });

    testWidgets('"Continua" waits for a name', (tester) async {
      await _pumpWelcome(tester);
      await _tick(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(_continueButton(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Bruno');
      await tester.pump();
      expect(_continueButton(tester).onPressed, isNotNull);
    });

    testWidgets('starts with an empty name when Google has none', (
      tester,
    ) async {
      await _pumpWelcome(tester, user: const SessionUser(id: 'user-carla'));
      await _tick(tester);

      expect(find.widgetWithText(TextField, ''), findsOneWidget);
      expect(_continueButton(tester).onPressed, isNull);
    });

    testWidgets('saves the name without the spaces at both ends', (
      tester,
    ) async {
      final accounts = await _pumpWelcome(
        tester,
        user: const SessionUser(
          id: 'user-anna',
          name: 'Anna',
          avatarUrl: 'https://example.com/anna.png',
        ),
      );
      await tester.enterText(find.byType(TextField), '  Anna Maria  ');
      await _tick(tester);

      await _tapContinue(tester);

      expect(accounts.saves.single, (
        userId: 'user-anna',
        displayName: 'Anna Maria',
        avatarUrl: 'https://example.com/anna.png',
        noticeVersion: privacyNoticeVersion,
        isDemo: false,
      ));
      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('shows an indicator while it saves', (tester) async {
      final accounts = await _pumpWelcome(tester);
      accounts.saveGate = Completer<void>();
      await _tick(tester);

      await tester.tap(find.text('Continua'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_continueButton(tester).onPressed, isNull);

      accounts.saveGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HubScreen), findsOneWidget);
    });

    const errors = {
      'without a network': (
        offline,
        'Nessuna connessione. Controlla la rete e riprova.',
      ),
      'when Supabase refuses': (
        serverError,
        'Non è stato possibile salvare. Riprova.',
      ),
    };
    for (final MapEntry(key: name, value: (error, message)) in errors.entries) {
      testWidgets('says "$message" $name, and stays', (tester) async {
        final accounts = await _pumpWelcome(tester);
        accounts.saveError = error;
        await _tick(tester);

        await _tapContinue(tester);

        expect(find.widgetWithText(SnackBar, message), findsOneWidget);
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(_continueButton(tester).onPressed, isNotNull);
      });
    }

    test('a valid name fits the check of profiles', () {
      expect(isValidDisplayName('Anna'), isTrue);
      expect(isValidDisplayName('  Anna  '), isTrue);
      expect(isValidDisplayName(''), isFalse);
      expect(isValidDisplayName('   '), isFalse);
      expect(isValidDisplayName('a' * 80), isTrue);
      expect(isValidDisplayName('a' * 81), isFalse);
    });
  });

  group('with a new version of the notice', () {
    testWidgets('shows the checkbox only, and saves only the notice', (
      tester,
    ) async {
      final accounts = await _pumpWelcome(tester, status: oldNoticeAccount);

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(CookieAvatar), findsNothing);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(_continueButton(tester).onPressed, isNull);

      await _tick(tester);
      await _tapContinue(tester);

      expect(accounts.saves.single.displayName, isNull);
      expect(accounts.saves.single.noticeVersion, privacyNoticeVersion);
      expect(find.byType(HubScreen), findsOneWidget);
    });
  });

  testWidgets('the link opens the notice on Pages, not the checkbox', (
    tester,
  ) async {
    final opened = <Uri>[];
    await _pumpWelcome(tester, openedLinks: opened);

    await tester.tapOnText(find.textRange.ofSubstring('informativa privacy'));
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse('https://example.pages.dev/privacy/')]);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('the text of the checkbox ticks it too', (tester) async {
    await _pumpWelcome(tester);

    await tester.tapOnText(find.textRange.ofSubstring('Ho letto'));
    await tester.pump();

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('"Esci dall\'account" in the menu asks to confirm', (
    tester,
  ) async {
    await _pumpWelcome(tester);

    await tester.tap(find.byIcon(Symbols.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Esci dall'account"));
    await tester.pumpAndSettle();
    expect(find.byType(SignOutDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Esci'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text(sessionLostMessage), findsNothing);
  });
}
