import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/design/highlight_card.dart';
import 'package:homemade/design/pressable.dart';
import 'package:homemade/features/auth/delete_demo_account.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/sign_out.dart';
import 'package:homemade/features/household/cash_amount.dart';
import 'package:homemade/features/household/create_household_screen.dart';
import 'package:homemade/features/household/household_choice_screen.dart';
import 'package:homemade/features/household/household_dates.dart';
import 'package:homemade/features/household/invite_screen.dart';
import 'package:homemade/features/household/join_household_screen.dart';
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

/// An invented today: a Saturday in the middle of March 2031.
final _now = DateTime(2031, 3, 15, 10, 30);

const _choicePath = '/household';
const _createPath = '/household/create';

/// A demo account without a household.
final AccountStatus _demoNoHousehold = noHouseholdAccount.copyWith(
  isDemo: true,
);

/// Pumps the app for an account in [status], without a household, on the
/// day of [_now], then opens [location].
///
/// The app starts on A7: a cold start never opens a sub-screen of the
/// household, which is never a destination (the startup screen comes
/// first, and forgets it).
Future<
  ({
    FakeAccountRepository accounts,
    FakeHouseholdRepository households,
    FakeAuthRepository auth,
  })
>
_pump(
  WidgetTester tester, {
  String location = _choicePath,
  AccountStatus status = noHouseholdAccount,
  DateTime? now,
  Size? window,
}) async {
  final accounts = FakeAccountRepository(status: status);
  final households = FakeHouseholdRepository();
  final auth = FakeAuthRepository();
  final router = await pumpApp(
    tester,
    location: _choicePath,
    auth: auth,
    accounts: accounts,
    households: households,
    now: now ?? _now,
    window: window,
  );
  if (location != _choicePath) {
    router.go(location);
    await tester.pumpAndSettle();
  }
  return (accounts: accounts, households: households, auth: auth);
}

/// The surface of the card whose title is [title].
Finder _card(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Pressable)).first;

/// The field of the name of the household.
Finder get _nameField => find.widgetWithText(TextField, householdNameLabel);

/// The field of the cash.
Finder get _cashField => find.widgetWithText(TextField, cashLabel);

/// The "Crea" button.
FilledButton _createButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

/// The text shown in the field of the start date.
Finder _dateText(String text) =>
    find.descendant(of: find.byType(InputDecorator), matching: find.text(text));

/// Opens the date picker from the field of the start date.
Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.text(startDateLabel));
  await tester.pumpAndSettle();
}

/// Picks the day [day] of the month shown, then "OK".
Future<void> _pickDay(WidgetTester tester, int day) async {
  await _openPicker(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(CalendarDatePicker),
      matching: find.text('$day'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Writes the name and taps "Crea".
Future<void> _create(
  WidgetTester tester, {
  String name = 'Casa di prova',
}) async {
  await tester.enterText(_nameField, name);
  await tester.pump();
  await tester.ensureVisible(find.text(createHouseholdLabel));
  await tester.pumpAndSettle();
  await tester.tap(find.text(createHouseholdLabel));
  await tester.pumpAndSettle();
}

/// The message of the snackbar, if any.
Finder _snackBar(String message) => find.widgetWithText(SnackBar, message);

void main() {
  usePhoneWindow();
  // The real fonts: the layout follows the boards, and the text at 200%.
  setUpAll(loadAppFonts);

  group('dates of A8', () {
    test('the start date proposed is the first of the month', () {
      expect(defaultStartDate(DateTime(2031, 3, 15)), DateTime(2031, 3));
      expect(defaultStartDate(DateTime(2031, 3)), DateTime(2031, 3));
    });

    test('the start dates go from 90 days before to 12 months after', () {
      expect(firstStartDate(DateTime(2031, 3, 15)), DateTime(2030, 12, 15));
      expect(lastStartDate(DateTime(2031, 3, 15)), DateTime(2032, 3, 15));
      // As Postgres adds months: the last day of a shorter month.
      expect(lastStartDate(DateTime(2032, 2, 29)), DateTime(2033, 2, 28));
    });

    test('a date out of the range is brought back to its end', () {
      final today = DateTime(2031, 3, 15);
      expect(clampStartDate(DateTime(2030), today), DateTime(2030, 12, 15));
      expect(clampStartDate(DateTime(2040), today), DateTime(2032, 3, 15));
      expect(clampStartDate(DateTime(2031, 3), today), DateTime(2031, 3));
    });

    test('the date is written in Italian, with "1°" for the first only', () {
      final today = DateTime(2031, 3, 15);
      expect(formatStartDate(DateTime(2031, 3), today), '1° marzo 2031');
      expect(formatStartDate(DateTime(2031, 3, 2), today), '2 marzo 2031');
      expect(
        formatStartDate(DateTime(2031, 12, 31), today),
        '31 dicembre 2031',
      );
      expect(formatStartDate(today, today), '15 marzo 2031 · oggi');
      expect(
        formatStartDate(DateTime(2031, 3), DateTime(2031, 3)),
        '1° marzo 2031 · oggi',
      );
    });

    test('the screen reader hears the date, and "oggi" first', () {
      final today = DateTime(2031, 3, 15);
      expect(
        startDateSemantics(DateTime(2031, 3), today),
        'Data di inizio: 1° marzo 2031. Tocca per cambiarla',
      );
      expect(
        startDateSemantics(today, today),
        'Data di inizio: oggi, 15 marzo 2031. Tocca per cambiarla',
      );
    });

    test('the date goes to Postgres as yyyy-mm-dd', () {
      expect(isoDate(DateTime(2031, 3)), '2031-03-01');
      expect(isoDate(DateTime(2031, 11, 17)), '2031-11-17');
    });
  });

  group('the amount of cash', () {
    TextEditingValue edit(String from, String to) =>
        const CashAmountFormatter().formatEditUpdate(
          TextEditingValue(text: from),
          TextEditingValue(text: to),
        );

    test('accepts digits and one comma, with up to two decimals', () {
      expect(edit('', '12').text, '12');
      expect(edit('12', '12,').text, '12,');
      expect(edit('12,', '12,5').text, '12,5');
      expect(edit('12,5', '12,50').text, '12,50');
      expect(edit('', ',5').text, ',5');
    });

    test('turns the point into a comma', () {
      expect(edit('12', '12.').text, '12,');
      expect(edit('', '12.50').text, '12,50');
    });

    test('refuses a third decimal, a second comma, a sign, letters', () {
      expect(edit('12,50', '12,505').text, '12,50');
      expect(edit('12,5', '12,5,').text, '12,5');
      expect(edit('12', '-12').text, '12');
      expect(edit('12', '+12').text, '12');
      expect(edit('12', '12a').text, '12');
      expect(edit('12', '1 2').text, '12');
      expect(edit('', '1.234,56').text, '');
    });

    test('goes up to 999.999,99', () {
      expect(edit('99999', '999999').text, '999999');
      expect(edit('999999', '9999999').text, '999999');
      expect(edit('999999,9', '999999,99').text, '999999,99');
      expect(parseCashCents('999999,99'), maxCashCents);
    });

    test('becomes cents, and nothing without a digit', () {
      expect(parseCashCents('12,50'), 1250);
      expect(parseCashCents('12,5'), 1250);
      expect(parseCashCents('12,'), 1200);
      expect(parseCashCents('12'), 1200);
      expect(parseCashCents(',5'), 50);
      expect(parseCashCents('0'), 0);
      expect(parseCashCents('12.50'), 1250);
      expect(parseCashCents(''), isNull);
      expect(parseCashCents(','), isNull);
    });
  });

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
      expect(find.byType(CreateHouseholdScreen), findsOneWidget);

      await systemBack(tester);
      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
    });

    testWidgets('"Ho un invito" opens A10, and back returns', (tester) async {
      await _pump(tester);

      await tester.tap(find.text(joinCardTitle));
      await tester.pumpAndSettle();
      expect(find.byType(JoinHouseholdScreen), findsOneWidget);

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

  group('A8', () {
    testWidgets('opens with an empty name and the first of the month', (
      tester,
    ) async {
      await _pump(tester, location: _createPath);

      expect(find.text(createHouseholdTitle), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(tester.widget<TextField>(_nameField).controller?.text, isEmpty);
      expect(_dateText('1° marzo 2031'), findsOneWidget);
      expect(find.text(startDateHelper), findsOneWidget);
      expect(_cashField, findsNothing);
      expect(_createButton(tester).onPressed, isNull);
    });

    testWidgets('the name starts with a capital letter', (tester) async {
      await _pump(tester, location: _createPath);

      final field = tester.widget<TextField>(_nameField);
      expect(field.textCapitalization, TextCapitalization.sentences);
    });

    testWidgets('"Crea" waits for a name of 1 to 80 characters', (
      tester,
    ) async {
      await _pump(tester, location: _createPath);

      await tester.enterText(_nameField, '   ');
      await tester.pump();
      expect(_createButton(tester).onPressed, isNull);

      await tester.enterText(_nameField, 'Casa di prova');
      await tester.pump();
      expect(_createButton(tester).onPressed, isNotNull);

      // The field stops at 80 characters.
      await tester.enterText(_nameField, 'a' * 81);
      await tester.pump();
      expect(tester.widget<TextField>(_nameField).controller?.text, 'a' * 80);
      expect(isValidHouseholdName('a' * 80), isTrue);
      expect(isValidHouseholdName('  ${'a' * 80}  '), isTrue);
      expect(isValidHouseholdName('a' * 81), isFalse);
    });

    testWidgets('the date picker goes from 90 days before to 12 months '
        'after, in Italian', (tester) async {
      await _pump(tester, location: _createPath);

      await _openPicker(tester);

      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.firstDate, DateTime(2030, 12, 15));
      expect(picker.lastDate, DateTime(2032, 3, 15));
      expect(picker.initialDate, DateTime(2031, 3));
      expect(picker.currentDate, DateTime(2031, 3, 15));
      expect(
        Localizations.localeOf(tester.element(find.byType(DatePickerDialog))),
        const Locale('it'),
      );
    });

    testWidgets('the field of the date reads as one button', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, location: _createPath);

      expect(
        find.bySemanticsLabel(
          'Data di inizio: 1° marzo 2031. Tocca per cambiarla',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('today shows "· oggi" and the field of the cash', (
      tester,
    ) async {
      await _pump(tester, location: _createPath);

      await _pickDay(tester, 15);

      expect(_dateText('15 marzo 2031 · oggi'), findsOneWidget);
      expect(_cashField, findsOneWidget);
      expect(find.text(cashHelper), findsOneWidget);
      // The helper of the date sits where Material puts the one of the cash.
      expect(
        tester.getTopLeft(find.text(startDateHelper)).dx,
        tester.getTopLeft(find.text(cashHelper)).dx,
      );
      expect(find.text('0,00'), findsOneWidget);
      expect(find.text('€'), findsOneWidget);
      final field = tester.widget<TextField>(_cashField);
      expect(
        field.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );

      // Another day: the field goes.
      await _pickDay(tester, 14);
      expect(_dateText('14 marzo 2031'), findsOneWidget);
      expect(_cashField, findsNothing);
    });

    testWidgets('on the first of the month, the date proposed is today', (
      tester,
    ) async {
      await _pump(tester, location: _createPath, now: DateTime(2031, 3, 1, 9));

      expect(_dateText('1° marzo 2031 · oggi'), findsOneWidget);
      expect(_cashField, findsOneWidget);
    });

    testWidgets('the cash field filters what is written', (tester) async {
      await _pump(tester, location: _createPath);
      await _pickDay(tester, 15);

      await tester.enterText(_cashField, '12.5');
      await tester.pump();
      expect(tester.widget<TextField>(_cashField).controller?.text, '12,5');

      await tester.enterText(_cashField, '-3');
      await tester.pump();
      expect(tester.widget<TextField>(_cashField).controller?.text, '12,5');
    });

    testWidgets('"Crea" sends the name without spaces, the date and the cash '
        'of today, then A9', (tester) async {
      final pumped = await _pump(tester, location: _createPath);
      await _pickDay(tester, 15);
      await tester.enterText(_cashField, '12,50');

      await _create(tester, name: '  Casa di prova  ');

      final call = pumped.households.calls.single;
      expect(call.name, 'Casa di prova');
      expect(call.startDate, DateTime(2031, 3, 15));
      expect(call.cashOpeningCents, 1250);
      expect(find.byType(InviteScreen), findsOneWidget);
    });

    testWidgets('without cash written, sends no balance', (tester) async {
      final pumped = await _pump(tester, location: _createPath);
      await _pickDay(tester, 15);

      await _create(tester);

      expect(pumped.households.calls.single.cashOpeningCents, isNull);
    });

    testWidgets('the cash written stays, but goes only with today', (
      tester,
    ) async {
      final pumped = await _pump(tester, location: _createPath);
      await _pickDay(tester, 15);
      await tester.enterText(_cashField, '12,50');
      await _pickDay(tester, 1);
      expect(_cashField, findsNothing);

      await _pickDay(tester, 15);
      expect(tester.widget<TextField>(_cashField).controller?.text, '12,50');

      await _pickDay(tester, 1);
      await _create(tester);

      final call = pumped.households.calls.single;
      expect(call.startDate, DateTime(2031, 3));
      expect(call.cashOpeningCents, isNull);
    });

    testWidgets('shows an indicator while it creates', (tester) async {
      final pumped = await _pump(tester, location: _createPath);
      pumped.households.gate = Completer<void>();

      await tester.enterText(_nameField, 'Casa di prova');
      await tester.pump();
      await tester.tap(find.text(createHouseholdLabel));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_createButton(tester).onPressed, isNull);
      expect(tester.widget<TextField>(_nameField).enabled, isFalse);

      pumped.households.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(InviteScreen), findsOneWidget);
    });

    final errors = <String, (Exception, String)>{
      'without a network': (
        offline,
        'Nessuna connessione. Controlla la rete e riprova.',
      ),
      'with a start date out of range': (
        householdError('start_date_out_of_range'),
        "La data di inizio non è più valida: scegline un'altra.",
      ),
      'without a profile': (
        householdError('no_profile'),
        'Non è stato possibile creare la casa. Riprova.',
      ),
      'with any other error': (
        serverError,
        'Non è stato possibile creare la casa. Riprova.',
      ),
    };
    for (final MapEntry(key: name, value: (error, message)) in errors.entries) {
      testWidgets('$name says "$message" and stays', (tester) async {
        final pumped = await _pump(tester, location: _createPath);
        pumped.households.error = error;

        await _create(tester);

        expect(_snackBar(message), findsOneWidget);
        expect(find.byType(CreateHouseholdScreen), findsOneWidget);
        expect(_createButton(tester).onPressed, isNotNull);
      });
    }

    testWidgets('already a member: no message, the state is read again and '
        'the start goes on', (tester) async {
      final pumped = await _pump(tester, location: _createPath);
      pumped.households.error = householdError('already_member');
      pumped.accounts.status = noHouseholdAccount.copyWith(hasMember: true);
      final reads = pumped.accounts.reads;

      await _create(tester);

      expect(pumped.accounts.reads, reads + 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('a retry sends the same id', (tester) async {
      final pumped = await _pump(tester, location: _createPath);
      pumped.households.error = offline;
      await _create(tester);
      expect(find.byType(CreateHouseholdScreen), findsOneWidget);

      pumped.households.error = null;
      await tester.tap(find.text(createHouseholdLabel));
      await tester.pumpAndSettle();

      final [first, second] = pumped.households.calls;
      expect(second.id, first.id);
      expect(first.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(find.byType(InviteScreen), findsOneWidget);
    });

    testWidgets('back returns to A7', (tester) async {
      await _pump(tester, location: _createPath);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
    });

    testWidgets('the layout follows the board', (tester) async {
      await _pump(tester, location: _createPath, window: const Size(390, 844));

      expect(tester.getSize(find.byType(AppBar)).height, AppSizes.topBarHeight);
      final name = tester.getRect(find.byType(TextField));
      expect(name.left, AppSpacing.screenMargin);
      expect(name.top, AppSizes.topBarHeight + AppSpacing.md);
      final button = tester.getRect(find.byType(FilledButton));
      expect(button, const Rect.fromLTRB(16, 764, 374, 820));
    });

    group('with the text at 200% or the keyboard open', () {
      for (final window in const [Size(360, 640), Size(1280, 800)]) {
        final size = '${window.width.toInt()} × ${window.height.toInt()}';
        testWidgets('cuts nothing at $size, and "Crea" is reachable', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = AppTextScale.max;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final pumped = await _pump(
            tester,
            location: _createPath,
            window: window,
          );
          await _pickDay(tester, 15);

          expect(tester.takeException(), isNull);
          expect(_cashField, findsOneWidget);
          await _create(tester);
          expect(pumped.households.calls, hasLength(1));
        });
      }

      testWidgets('with the keyboard open, "Crea" stays reachable', (
        tester,
      ) async {
        const window = Size(360, 640);
        const keyboard = 300.0;
        final pumped = await _pump(
          tester,
          location: _createPath,
          window: window,
        );
        await _pickDay(tester, 15);

        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboard * tester.view.devicePixelRatio,
        );
        addTearDown(tester.view.resetViewInsets);
        await tester.showKeyboard(_nameField);
        await tester.enterText(_nameField, 'Casa di prova');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text(createHouseholdLabel));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(FilledButton)).bottom,
          lessThanOrEqualTo(window.height - keyboard),
        );
        await tester.tap(find.text(createHouseholdLabel));
        await tester.pumpAndSettle();
        expect(pumped.households.calls, hasLength(1));
      });
    });
  });
}
