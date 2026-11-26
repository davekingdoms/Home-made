import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/design/highlight_card.dart';
import 'package:homemade/design/pressable.dart';
import 'package:homemade/features/auth/delete_demo_account.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/sign_out.dart';
import 'package:homemade/features/household/household_choice_screen.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/text_scale.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/design_harness.dart';
import 'helpers/fake_auth_repository.dart';
import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

const _choicePath = '/household';

/// A demo account without a household.
final AccountStatus _demoNoHousehold = noHouseholdAccount.copyWith(
  isDemo: true,
);

/// Pumps the app on A7 for an account in [status], without a household.
Future<({FakeAccountRepository accounts, FakeAuthRepository auth})> _pump(
  WidgetTester tester, {
  AccountStatus status = noHouseholdAccount,
  Size? window,
}) async {
  final accounts = FakeAccountRepository(status: status);
  final auth = FakeAuthRepository();
  await pumpApp(
    tester,
    location: _choicePath,
    auth: auth,
    accounts: accounts,
    window: window,
  );
  return (accounts: accounts, auth: auth);
}

/// The surface of the card whose title is [title].
Finder _card(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Pressable)).first;

/// The message of the snackbar, if any.
Finder _snackBar(String message) => find.widgetWithText(SnackBar, message);

void main() {
  usePhoneWindow();
  // The real fonts: the layout follows the boards, and the text at 200%.
  setUpAll(loadAppFonts);

  group('the household step', () {
    testWidgets('without a household the app opens A7', (tester) async {
      await pumpApp(
        tester,
        accounts: FakeAccountRepository(status: noHouseholdAccount),
      );

      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
    });

    testWidgets('with a household the app opens the hub', (tester) async {
      await pumpApp(tester);

      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('offline, a saved state without a household opens A7', (
      tester,
    ) async {
      final store = MemoryLocalStore();
      await pumpApp(
        tester,
        accounts: FakeAccountRepository(status: noHouseholdAccount),
        store: store,
      );
      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);

      // A new start, without a network: the state saved by the first one.
      await tester.pumpWidget(const SizedBox());
      await pumpApp(
        tester,
        accounts: FakeAccountRepository()..readError = offline,
        store: store,
      );
      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
    });
  });

  group('A7', () {
    testWidgets('greets with the first word of the name', (tester) async {
      await _pump(tester);

      expect(find.text('Ciao, Anna'), findsOneWidget);
      expect(find.text(householdChoicePhrase), findsOneWidget);
      expect(find.text(createCardTitle), findsOneWidget);
      expect(find.text(createCardText), findsOneWidget);
      expect(find.text(joinCardTitle), findsOneWidget);
      expect(find.text(joinCardText), findsOneWidget);
      expect(find.text(singleMemberLine), findsOneWidget);
    });

    testWidgets('without a name says "Ciao"', (tester) async {
      await _pump(
        tester,
        status: const AccountStatus(
          hasProfile: true,
          noticeVersion: privacyNoticeVersion,
          hasMember: false,
        ),
      );

      expect(find.text('Ciao'), findsOneWidget);
    });

    test('the greeting takes the first word only', () {
      expect(householdGreeting('Anna'), 'Ciao, Anna');
      expect(householdGreeting('  Anna   Maria Rossi '), 'Ciao, Anna');
      expect(householdGreeting(''), 'Ciao');
      expect(householdGreeting('   '), 'Ciao');
      expect(householdGreeting(null), 'Ciao');
    });

    testWidgets('has the menu only in the top bar, no title, no back', (
      tester,
    ) async {
      await _pump(tester);

      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.title, isNull);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byIcon(Symbols.more_vert_rounded), findsOneWidget);
      // The content starts just under the bar.
      expect(
        tester.getTopLeft(find.text('Ciao, Anna')).dy,
        tester.getBottomLeft(find.byType(AppBar)).dy,
      );
    });

    testWidgets('the menu has "Esci dall\'account" only, for a real account', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byIcon(Symbols.more_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.text("Esci dall'account"), findsOneWidget);
      expect(find.text(deleteDemoAccountLabel), findsNothing);
    });

    testWidgets('"Esci dall\'account" asks to confirm, then signs out', (
      tester,
    ) async {
      final pumped = await _pump(tester);

      await tester.tap(find.byIcon(Symbols.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Esci dall'account"));
      await tester.pumpAndSettle();
      expect(find.byType(SignOutDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Esci'));
      await tester.pumpAndSettle();

      expect(pumped.auth.signOuts, 1);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text(sessionLostMessage), findsNothing);
    });

    testWidgets('for a demo account the menu can delete it, as I2 does', (
      tester,
    ) async {
      final pumped = await _pump(tester, status: _demoNoHousehold);

      await tester.tap(find.byIcon(Symbols.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text("Esci dall'account"), findsOneWidget);
      await tester.tap(find.text(deleteDemoAccountLabel));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteDemoAccountDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Elimina'));
      await tester.pumpAndSettle();

      expect(pumped.accounts.deletions, 1);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text(sessionLostMessage), findsNothing);
    });

    testWidgets('"Annulla" deletes nothing', (tester) async {
      final pumped = await _pump(tester, status: _demoNoHousehold);

      await tester.tap(find.byIcon(Symbols.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(deleteDemoAccountLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(pumped.accounts.deletions, 0);
      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
    });

    final deleteErrors = <String, (Exception, String)>{
      'without a network': (
        offline,
        'Nessuna connessione. Controlla la rete e riprova.',
      ),
      'when Supabase refuses': (
        serverError,
        "Non è stato possibile eliminare l'account. Riprova.",
      ),
    };
    for (final MapEntry(key: name, value: (error, message))
        in deleteErrors.entries) {
      testWidgets('a deletion that fails $name says "$message"', (
        tester,
      ) async {
        final pumped = await _pump(tester, status: _demoNoHousehold);
        pumped.accounts.deleteError = error;

        await tester.tap(find.byIcon(Symbols.more_vert_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text(deleteDemoAccountLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Elimina'));
        await tester.pumpAndSettle();

        expect(_snackBar(message), findsOneWidget);
        expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
        expect(find.byIcon(Symbols.more_vert_rounded), findsOneWidget);
      });
    }

    testWidgets('shows an indicator in place of the menu while it deletes', (
      tester,
    ) async {
      final pumped = await _pump(tester, status: _demoNoHousehold);
      pumped.accounts.deleteGate = Completer<void>();

      await tester.tap(find.byIcon(Symbols.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(deleteDemoAccountLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Elimina'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Symbols.more_vert_rounded), findsNothing);

      pumped.accounts.deleteGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('each card is one button for the screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      expect(
        tester.getSemantics(_card(createCardTitle)),
        isSemantics(
          label: '$createCardTitle. $createCardText',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(_card(joinCardTitle)),
        isSemantics(
          label: '$joinCardTitle. $joinCardText',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('"Crea una casa" opens A8, and back returns', (tester) async {
      await _pump(tester);

      await tester.tap(find.text(createCardTitle));
      await tester.pumpAndSettle();
      expect(find.text('A8 · Crea casa'), findsOneWidget);

      await systemBack(tester);
      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
    });

    testWidgets('"Ho un invito" opens the placeholder of A10, and back '
        'returns', (tester) async {
      await _pump(tester);

      await tester.tap(find.text(joinCardTitle));
      await tester.pumpAndSettle();
      expect(find.text('A10 · Entra con invito'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
    });

    testWidgets('the cards and the line follow the board', (tester) async {
      await _pump(tester, window: const Size(390, 844));
      final scheme = Theme.of(
        tester.element(find.byType(HouseholdChoiceScreen)),
      ).colorScheme;
      final colors = tester
          .element(find.byType(HouseholdChoiceScreen))
          .appColors;

      final create = tester.getRect(_card(createCardTitle));
      final join = tester.getRect(_card(joinCardTitle));
      final phrase = tester.getRect(find.text(householdChoicePhrase));
      expect(create.left, AppSpacing.screenMargin);
      expect(create.width, 390 - 2 * AppSpacing.screenMargin);
      expect(create.top, phrase.bottom + AppSpacing.sectionGap);
      expect(join.top, create.bottom + AppSpacing.sectionGap);
      expect(find.byType(HighlightCard), findsOneWidget);

      // The line 24 above the bottom edge.
      final line = tester.getRect(find.text(singleMemberLine));
      expect(line.bottom, 844 - AppSpacing.xl);

      final joinCard = tester.widget<Pressable>(_card(joinCardTitle));
      expect(joinCard.color, scheme.surfaceContainerLow);
      final lineText = tester.widget<Text>(find.text(singleMemberLine));
      expect(lineText.style?.color, colors.testoTerziario);
      expect(lineText.textAlign, TextAlign.center);
      final link = tester.widget<Icon>(find.byIcon(Symbols.link_rounded));
      expect(link.color, scheme.primary);
      expect(link.size, 28);
      final house = tester.widget<Icon>(find.byIcon(Symbols.add_home_rounded));
      expect(house.color, scheme.onTertiary);
      expect(house.size, 28);
    });

    group('with the text at 200%', () {
      for (final window in const [Size(360, 640), Size(1280, 800)]) {
        final size = '${window.width.toInt()} × ${window.height.toInt()}';
        testWidgets('cuts nothing at $size and scrolls', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = AppTextScale.max;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pump(tester, window: window);

          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(_card(createCardTitle)).width,
            lessThanOrEqualTo(AppSizes.maxContentWidth),
          );
          await tester.ensureVisible(find.text(singleMemberLine));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.text(singleMemberLine)).bottom,
            lessThanOrEqualTo(window.height),
          );
        });
      }
    });
  });
}
