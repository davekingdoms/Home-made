import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/storage/local_store.dart';
import 'package:homemade/design/cookie.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/sign_out.dart';
import 'package:homemade/features/auth/welcome_screen.dart';
import 'package:homemade/features/household/household_choice_screen.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/text_scale.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/design_harness.dart';
import 'helpers/fake_auth_repository.dart';
import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

/// The "Continua" button.
FilledButton _continueButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

Future<void> _tick(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
}

/// Taps "Continua", at the bottom of the column: under the fold of the
/// window of the tests, so the column scrolls there first.
Future<void> _tapContinue(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Continua'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continua'));
  await tester.pumpAndSettle();
}

/// The card of the checkbox.
Finder get _noticeCard => find.ancestor(
  of: find.text(noticeCheckboxLabel),
  matching: find.byType(Card),
);

/// The button that opens the notice.
Finder get _readButton => find.ancestor(
  of: find.text(readNoticeLabel),
  matching: find.byType(TextButton),
);

/// The visible pill of [button], without the touch target around it.
Finder _pill(Finder button) =>
    find.descendant(of: button, matching: find.byType(Material)).first;

/// A store with the choice of "Modalità demo" saved.
MemoryLocalStore _storeWithDemoChoice() =>
    MemoryLocalStore()..values[StartupGate.demoChoiceKey] = 'true';

/// Pumps first access for an account in [status].
Future<FakeAccountRepository> _pumpWelcome(
  WidgetTester tester, {
  AccountStatus status = newAccount,
  SessionUser user = anna,
  List<Uri>? openedLinks,
  LocalStore? store,
  Size? window,
}) async {
  final accounts = FakeAccountRepository(status: status);
  await pumpApp(
    tester,
    location: '/welcome',
    auth: FakeAuthRepository(user: user),
    accounts: accounts,
    openedLinks: openedLinks,
    store: store,
    window: window,
  );
  expect(find.byType(WelcomeScreen), findsOneWidget);
  return accounts;
}

void main() {
  group('the whole first access', () {
    testWidgets('shows the profile, the card of the notice and "Continua"', (
      tester,
    ) async {
      await _pumpWelcome(tester);

      expect(find.text(welcomeTitle), findsOneWidget);
      expect(find.text(welcomePhrase), findsOneWidget);
      expect(find.byType(CookieAvatar), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Anna'), findsOneWidget);
      expect(find.text(nameHelperText), findsOneWidget);
      expect(find.text(demoAccountNotice), findsNothing);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text(noticeCheckboxLabel), findsOneWidget);
      expect(find.text(readNoticeLabel), findsOneWidget);
      expect(find.text(noticeVersionLine), findsOneWidget);
      expect(find.text('Continua'), findsOneWidget);
      // The note of the mockup on the photo is not a text of the app.
      expect(find.textContaining('Foto'), findsNothing);
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
      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
    });

    testWidgets('shows an indicator while it saves', (tester) async {
      final accounts = await _pumpWelcome(tester);
      accounts.saveGate = Completer<void>();
      await _tick(tester);

      await tester.ensureVisible(find.text('Continua'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continua'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_continueButton(tester).onPressed, isNull);

      accounts.saveGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
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
    testWidgets('shows "Informativa aggiornata" and the card only', (
      tester,
    ) async {
      await _pumpWelcome(tester, status: oldNoticeAccount);

      expect(find.text(noticeUpdatedTitle), findsOneWidget);
      expect(find.text(noticeUpdatedPhrase), findsOneWidget);
      expect(find.text(welcomeTitle), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(CookieAvatar), findsNothing);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text(readNoticeLabel), findsOneWidget);
      expect(find.text(noticeVersionLine), findsNothing);
    });

    testWidgets('saves only the notice', (tester) async {
      final accounts = await _pumpWelcome(tester, status: oldNoticeAccount);
      expect(_continueButton(tester).onPressed, isNull);

      await _tick(tester);
      await _tapContinue(tester);

      expect(accounts.saves.single.displayName, isNull);
      expect(accounts.saves.single.noticeVersion, privacyNoticeVersion);
      expect(find.byType(HubScreen), findsOneWidget);
    });
  });

  group('the card of the notice', () {
    for (final status in [newAccount, oldNoticeAccount]) {
      final variant = status.hasProfile ? 'with the checkbox only' : 'whole';
      testWidgets('"Leggi l\'informativa" opens the notice ($variant)', (
        tester,
      ) async {
        final opened = <Uri>[];
        await _pumpWelcome(tester, status: status, openedLinks: opened);

        await tester.tap(find.text(readNoticeLabel));
        await tester.pumpAndSettle();

        expect(opened, [Uri.parse('https://example.pages.dev/privacy/')]);
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      });
    }

    testWidgets('the text of the checkbox ticks it too', (tester) async {
      await _pumpWelcome(tester);

      await tester.tap(find.text(noticeCheckboxLabel));
      await tester.pump();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      await tester.tap(find.text(noticeCheckboxLabel));
      await tester.pump();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });

    testWidgets('the row of the checkbox reads as one checkbox', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpWelcome(tester);

      expect(
        tester.getSemantics(find.byType(Checkbox)),
        isSemantics(
          label: noticeCheckboxLabel,
          hasCheckedState: true,
          isChecked: false,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('"Leggi l\'informativa" has the icon after the text', (
      tester,
    ) async {
      await _pumpWelcome(tester);

      final icon = find.descendant(
        of: _readButton,
        matching: find.byIcon(Symbols.open_in_new_rounded),
      );
      expect(icon, findsOneWidget);
      expect(tester.getSize(icon), const Size.square(18));
      expect(
        tester.getTopLeft(icon).dx,
        greaterThan(tester.getTopRight(find.text(readNoticeLabel)).dx),
      );
    });
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

  group('A3 at 390 × 844', () {
    // The real font: the font of the tests draws every letter as a square,
    // much wider than Google Sans Flex, and wraps the lines.
    setUpAll(loadAppFonts);

    const window = Size(390, 844);

    testWidgets('keeps the measures of the mockup, whole', (tester) async {
      await _pumpWelcome(tester, window: window);

      // Just under the top bar, 64 high.
      final title = tester.getRect(find.text(welcomeTitle));
      expect(title.topLeft, const Offset(20, 64));
      expect(title.height, 40);
      final phrase = tester.getRect(find.text(welcomePhrase));
      expect(phrase.top, title.bottom + AppSpacing.xs);
      expect(phrase.left, 20);

      final photo = tester.getRect(find.byType(CookieAvatar));
      expect(photo.size, const Size.square(96));
      expect(photo.center.dx, 195);
      expect(photo.top, phrase.bottom + AppSpacing.sectionGap);

      final field = tester.getRect(find.byType(TextField));
      expect(field.left, 16);
      expect(field.right, 374);
      expect(field.top, photo.bottom + AppSpacing.sectionGap);
      final helper = tester.getRect(find.text(nameHelperText));
      // Under the outline, 56 high, 4 below.
      expect(helper.top, field.top + 56 + AppSpacing.xxs);

      final card = tester.getRect(_noticeCard);
      expect(card.left, 16);
      expect(card.right, 374);
      expect(card.top, helper.bottom + AppSpacing.sectionGap);
      final box = tester.getRect(find.byType(Checkbox));
      expect(box.center, Offset(16 + 8 + 24, card.top + 4 + 28));
      final read = tester.getRect(_pill(_readButton));
      expect(read.height, 40);
      expect(read.left, 16 + 8 + 8);
      final version = tester.getRect(find.text(noticeVersionLine));
      expect(version.top, read.bottom + AppSpacing.xxs);
      expect(version.left, 16 + 8 + 8);
      expect(card.bottom, version.bottom + AppSpacing.sm);

      expect(
        tester.getRect(find.byType(FilledButton)),
        const Rect.fromLTRB(16, 764, 374, 820),
      );
    });

    testWidgets('keeps the measures of the mockup, notice only', (
      tester,
    ) async {
      await _pumpWelcome(tester, status: oldNoticeAccount, window: window);

      final title = tester.getRect(find.text(noticeUpdatedTitle));
      expect(title.topLeft, const Offset(20, 64));
      final phrase = tester.getRect(find.text(noticeUpdatedPhrase));
      expect(phrase.top, title.bottom + AppSpacing.xs);

      final card = tester.getRect(_noticeCard);
      expect(card.top, phrase.bottom + AppSpacing.sectionGap);
      final read = tester.getRect(_pill(_readButton));
      expect(card.bottom, read.bottom + AppSpacing.sm);

      expect(
        tester.getRect(find.byType(FilledButton)),
        const Rect.fromLTRB(16, 764, 374, 820),
      );
    });
  });

  group('A3 with the text at 200%', () {
    setUpAll(loadAppFonts);

    for (final window in const [Size(360, 640), Size(1280, 800)]) {
      final size = '${window.width.toInt()} × ${window.height.toInt()}';
      testWidgets('fits $size, and "Continua" is reachable', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = AppTextScale.max;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // The longest A3: the line of a demo account too.
        await _pumpWelcome(
          tester,
          store: _storeWithDemoChoice(),
          window: window,
        );

        expect(tester.takeException(), isNull);
        expect(find.text(demoAccountNotice), findsOneWidget);
        expect(
          tester.getSize(find.byType(FilledButton)).width,
          lessThanOrEqualTo(AppSizes.maxContentWidth),
        );

        await _tick(tester);
        await _tapContinue(tester);
        expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
      });
    }

    testWidgets('fits with a new version of the notice', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = AppTextScale.max;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpWelcome(
        tester,
        status: oldNoticeAccount,
        window: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('A3 with the keyboard open', () {
    setUpAll(loadAppFonts);

    for (final textScale in [1.0, AppTextScale.max]) {
      testWidgets('cuts nothing and keeps "Continua" reachable, text at '
          '${(textScale * 100).toInt()}%', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const window = Size(360, 640);
        const keyboard = 300.0;
        await _pumpWelcome(tester, window: window);
        await _tick(tester);

        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboard * tester.view.devicePixelRatio,
        );
        addTearDown(tester.view.resetViewInsets);
        await tester.showKeyboard(find.byType(TextField));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // The field shows above the keyboard.
        expect(
          tester.getRect(find.byType(EditableText)).bottom,
          lessThanOrEqualTo(window.height - keyboard),
        );

        await tester.ensureVisible(find.text('Continua'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(FilledButton)).bottom,
          lessThanOrEqualTo(window.height - keyboard),
        );
        await tester.tap(find.text('Continua'));
        await tester.pumpAndSettle();
        expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
      });
    }
  });
}
