import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/welcome_screen.dart';
import 'package:homemade/features/household/create_household_screen.dart';
import 'package:homemade/features/household/household_choice_screen.dart';
import 'package:homemade/features/household/household_repository.dart';
import 'package:homemade/features/household/invite_screen.dart'
    show householdFullMessage;
import 'package:homemade/features/household/join_household_screen.dart';
import 'package:homemade/features/household/pending_invite.dart';
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

/// An invented today: a Saturday in the middle of March 2031.
final _now = DateTime(2031, 3, 15, 10, 30);

/// The link of an invented invite, as an App Link brings it.
const _link = 'https://example.pages.dev/invite/#t=$inventedToken&c=K7QMX2PA';

/// What a pumped A10 leaves around it.
typedef _Pumped = ({
  FakeHouseholdRepository households,
  FakeAccountRepository accounts,
  MemoryLocalStore store,
});

/// Pumps A7 for an account without a household on [_now] and opens A10
/// with "Ho un invito"; with [pendingInvite], the invite of the link is
/// saved on the device first, and A10 opens by itself.
Future<_Pumped> _pump(
  WidgetTester tester, {
  FakeHouseholdRepository? households,
  AccountStatus status = noHouseholdAccount,
  bool pendingInvite = false,
  Size window = const Size(390, 844),
}) async {
  final repository = households ?? FakeHouseholdRepository();
  final accounts = FakeAccountRepository(status: status);
  final store = MemoryLocalStore();
  if (pendingInvite) {
    store.values[StartupGate.pendingInviteKey] = jsonEncode(
      PendingInvite(
        token: inventedToken,
        code: 'K7QMX2PA',
        savedAt: _now,
      ).toJson(),
    );
  }
  await pumpApp(
    tester,
    location: '/household',
    accounts: accounts,
    households: repository,
    store: store,
    now: _now,
    window: window,
  );
  if (!pendingInvite) await _tapText(tester, joinCardTitle);
  return (households: repository, accounts: accounts, store: store);
}

Finder get _codeField => find.widgetWithText(TextField, inviteCodeLabel);

String _codeText(WidgetTester tester) =>
    tester.widget<TextField>(_codeField).controller!.text;

/// Writes [code] and taps "Continua".
Future<void> _continue(WidgetTester tester, [String code = 'K7QM X2PA']) async {
  await tester.enterText(_codeField, code);
  await tester.pump();
  await tester.tap(find.text(joinContinueLabel));
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

FilledButton _button(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(
      find.ancestor(of: find.text(label), matching: find.byType(FilledButton)),
    );

String? _snackBar(WidgetTester tester) {
  final bar = find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(Text),
  );
  return bar.evaluate().isEmpty ? null : tester.widget<Text>(bar.first).data;
}

/// The preview of "Casa di prova", started on [start], with [members].
InvitePreviewResult _preview({
  DateTime? start,
  List<String> members = const ['Anna Rossi', 'Bruno'],
  String? inviter = 'Anna Rossi',
}) => (
  preview: InvitePreview(
    householdName: 'Casa di prova',
    inviterName: inviter,
    memberNames: members,
    householdStartDate: start ?? DateTime(2031, 3),
  ),
  error: null,
);

/// The text shown in the field of the start date.
Finder _dateText(String text) =>
    find.descendant(of: find.byType(InputDecorator), matching: find.text(text));

/// Picks the day [day] of the month shown in the date picker, then "OK".
Future<void> _pickDay(WidgetTester tester, int day) async {
  await tester.tap(find.text(joinStartDateLabel));
  await tester.pumpAndSettle();
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

void main() {
  setUpAll(loadAppFonts);

  group('texts of A10', () {
    test('who invites goes by the first word of the name', () {
      expect(invitedByText('Anna Rossi'), 'Ti invita Anna');
    });

    test('the members go by the first words, joined in Italian', () {
      expect(memberNamesText(['Anna Rossi']), 'Anna');
      expect(memberNamesText(['Anna Rossi', 'Bruno']), 'Anna e Bruno');
      expect(
        memberNamesText(['Anna', 'Bruno Verdi', 'Carla']),
        'Anna, Bruno e Carla',
      );
    });

    test('the start date of the household is written as in A8', () {
      expect(
        keepsAccountsSinceText(DateTime(2026, 11)),
        'Tiene i conti dal 1° novembre 2026',
      );
    });
  });

  group('the phase of the code', () {
    testWidgets('has the phrase, the field, "Continua" and the line on the '
        'link', (tester) async {
      await _pump(tester);

      expect(find.text(joinTitle), findsOneWidget);
      expect(find.text(joinCodePhrase), findsOneWidget);
      expect(_codeField, findsOneWidget);
      expect(find.text(joinLinkHint), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('the field takes letters and digits, in capitals, in two '
        'groups', (tester) async {
      await _pump(tester);

      await tester.enterText(_codeField, 'k7qm-x2pa');
      await tester.pump();
      expect(_codeText(tester), 'K7QM X2PA');

      await tester.enterText(_codeField, 'K7QM X2PA');
      await tester.pump();
      expect(_codeText(tester), 'K7QM X2PA');

      final field = tester.widget<TextField>(_codeField);
      expect(field.textCapitalization, TextCapitalization.characters);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    });

    testWidgets('"Continua" waits for 8 characters', (tester) async {
      await _pump(tester);

      await tester.enterText(_codeField, 'K7QM X2P');
      await tester.pump();
      expect(_button(tester, joinContinueLabel).onPressed, isNull);

      await tester.enterText(_codeField, 'K7QM X2PA');
      await tester.pump();
      expect(_button(tester, joinContinueLabel).onPressed, isNotNull);
    });

    testWidgets('"Continua" asks the preview with the code', (tester) async {
      final pumped = await _pump(tester);

      await _continue(tester, 'k7qm x2pa');

      expect(pumped.households.previews.single.code, 'K7QMX2PA');
      expect(pumped.households.previews.single.token, isNull);
      expect(find.text('Casa di prova'), findsOneWidget);
    });

    for (final error in [
      InviteError.invalid,
      InviteError.expired,
      InviteError.used,
      InviteError.revoked,
      InviteError.tooManyAttempts,
    ]) {
      testWidgets('${error.key} shows under the field', (tester) async {
        final households = FakeHouseholdRepository()
          ..previewResult = (preview: null, error: error);
        await _pump(tester, households: households);

        await _continue(tester);

        final field = tester.widget<TextField>(_codeField);
        expect(field.decoration!.errorText, inviteErrorText(error));
        expect(find.text(inviteErrorText(error)), findsOneWidget);
        expect(find.byIcon(Symbols.error_rounded), findsOneWidget);
      });
    }

    test('the texts of the errors are those of the specification', () {
      expect(
        inviteErrorText(InviteError.invalid),
        'Codice non valido. Controlla e riprova.',
      );
      expect(
        inviteErrorText(InviteError.expired),
        'Questo invito è scaduto: chiedine uno nuovo a chi ti ha invitato.',
      );
      expect(
        inviteErrorText(InviteError.used),
        'Questo invito è già stato usato.',
      );
      expect(
        inviteErrorText(InviteError.revoked),
        'Questo invito è stato annullato.',
      );
      expect(
        inviteErrorText(InviteError.tooManyAttempts),
        "Troppi tentativi: riprova tra un'ora.",
      );
    });

    testWidgets('the error goes when the code changes', (tester) async {
      final households = FakeHouseholdRepository()
        ..previewResult = (preview: null, error: InviteError.invalid);
      await _pump(tester, households: households);
      await _continue(tester);
      expect(find.text(inviteErrorText(InviteError.invalid)), findsOneWidget);

      await tester.enterText(_codeField, 'K7QM X2PB');
      await tester.pump();

      expect(find.text(inviteErrorText(InviteError.invalid)), findsNothing);
    });

    for (final (name, error, message) in [
      ('without network', offline as Exception, noConnectionMessage),
      ('any other error', serverError, previewFailedMessage),
      ('an unknown key', const UnknownInviteError('boh'), previewFailedMessage),
    ]) {
      testWidgets('$name says "$message"', (tester) async {
        final households = FakeHouseholdRepository()..previewThrows = error;
        await _pump(tester, households: households);

        await _continue(tester);

        expect(_snackBar(tester), message);
        expect(_codeField, findsOneWidget);
      });
    }

    testWidgets('shows an indicator while it asks', (tester) async {
      final households = FakeHouseholdRepository()
        ..previewGate = Completer<void>();
      await _pump(tester, households: households);

      await tester.enterText(_codeField, 'K7QM X2PA');
      await tester.pump();
      await tester.tap(find.text(joinContinueLabel));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      households.previewGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('back returns to A7', (tester) async {
      await _pump(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
    });

    testWidgets('the system back returns to A7 too', (tester) async {
      await _pump(tester);

      await systemBack(tester);

      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
    });
  });

  group('the phase of the preview', () {
    testWidgets('shows who invites, the household, the members and since '
        'when', (tester) async {
      await _pump(tester);

      await _continue(tester);

      expect(find.text('Ti invita Anna'), findsOneWidget);
      expect(find.text('Casa di prova'), findsOneWidget);
      expect(find.text('Anna e Bruno'), findsOneWidget);
      expect(find.text('Tiene i conti dal 1° marzo 2031'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('with three members, "Anna, Bruno e Carla"', (tester) async {
      final households = FakeHouseholdRepository()
        ..previewResult = _preview(members: ['Anna', 'Bruno', 'Carla']);
      await _pump(tester, households: households);

      await _continue(tester);

      expect(find.text('Anna, Bruno e Carla'), findsOneWidget);
    });

    testWidgets('the screen reader hears the region, not the cookies', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      await _continue(tester);

      expect(find.bySemanticsLabel(householdRegionLabel), findsOneWidget);
      expect(find.bySemanticsLabel('Anna'), findsNothing);
      semantics.dispose();
    });

    testWidgets('in a household already started, the date is today, back to '
        'the start of the household', (tester) async {
      await _pump(tester);
      await _continue(tester);

      expect(_dateText('15 marzo 2031 · oggi'), findsOneWidget);
      expect(
        find.text('Puoi anticiparla fino al 1° marzo 2031.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'La tua data di inizio: oggi, 15 marzo 2031. Tocca per anticiparla',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, cashLabel), findsOneWidget);
      expect(find.text(joinCashHelper), findsOneWidget);

      await tester.tap(find.text(joinStartDateLabel));
      await tester.pumpAndSettle();
      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(picker.firstDate, DateTime(2031, 3));
      expect(picker.lastDate, DateTime(2031, 3, 15));
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
    });

    testWidgets('an earlier date hides the cash and says so to the screen '
        'reader', (tester) async {
      await _pump(tester);
      await _continue(tester);

      await _pickDay(tester, 10);

      expect(_dateText('10 marzo 2031'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'La tua data di inizio: 10 marzo 2031. Tocca per cambiarla',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, cashLabel), findsNothing);
    });

    testWidgets('in a household that starts today the date does not change', (
      tester,
    ) async {
      final households = FakeHouseholdRepository()
        ..previewResult = _preview(start: DateTime(2031, 3, 15));
      await _pump(tester, households: households);
      await _continue(tester);

      expect(_dateText('15 marzo 2031 · oggi'), findsOneWidget);
      expect(
        find.text('La casa parte oggi: la tua data di inizio è la stessa.'),
        findsOneWidget,
      );
      await tester.tap(find.text(joinStartDateLabel));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsNothing);
      expect(find.widgetWithText(TextField, cashLabel), findsOneWidget);
    });

    testWidgets('in a household that has not started, the date is the one of '
        'the household, and fixed', (tester) async {
      final households = FakeHouseholdRepository()
        ..previewResult = _preview(start: DateTime(2031, 4));
      await _pump(tester, households: households);
      await _continue(tester);

      expect(_dateText('1° aprile 2031'), findsOneWidget);
      expect(
        find.text(
          'La casa parte il 1° aprile 2031: la tua data di inizio è la '
          'stessa.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'La casa parte il 1° aprile 2031: da quel giorno le quote '
          'predefinite sono uguali per tutti, e potrete cambiarle nelle '
          'impostazioni.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, cashLabel), findsNothing);
      await tester.tap(find.text(joinStartDateLabel));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsNothing);

      await _tapText(tester, joinLabel);
      final call = households.redeems.single;
      expect(call.startDate, isNull);
      expect(call.cashOpeningCents, isNull);
    });

    testWidgets('in a household already started, the box says the balance '
        'starts at zero', (tester) async {
      await _pump(tester);
      await _continue(tester);

      expect(
        find.text(
          'Parti con il conguaglio a zero e non vedi i movimenti precedenti '
          'alla tua data di inizio. Dalla tua data di inizio le quote '
          'predefinite sono uguali per tutti: potrete cambiarle nelle '
          'impostazioni.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('"Entra" sends the code, the date and the cash of today', (
      tester,
    ) async {
      final pumped = await _pump(tester);
      await _continue(tester);
      await tester.enterText(find.widgetWithText(TextField, cashLabel), '7,50');
      await tester.pump();

      await _tapText(tester, joinLabel);

      final call = pumped.households.redeems.single;
      expect(call.code, 'K7QMX2PA');
      expect(call.token, isNull);
      expect(call.startDate, DateTime(2031, 3, 15));
      expect(call.cashOpeningCents, 750);
      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('the cash written stays, but goes only with today', (
      tester,
    ) async {
      final pumped = await _pump(tester);
      await _continue(tester);
      await tester.enterText(find.widgetWithText(TextField, cashLabel), '7,50');
      await tester.pump();
      await _pickDay(tester, 10);

      await _tapText(tester, joinLabel);

      final call = pumped.households.redeems.single;
      expect(call.startDate, DateTime(2031, 3, 10));
      expect(call.cashOpeningCents, isNull);
    });

    testWidgets('the cash written comes back with today', (tester) async {
      await _pump(tester);
      await _continue(tester);
      await tester.enterText(find.widgetWithText(TextField, cashLabel), '7,50');
      await tester.pump();
      await _pickDay(tester, 10);
      await _pickDay(tester, 15);

      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, cashLabel))
            .controller!
            .text,
        '7,50',
      );
    });

    testWidgets('shows an indicator while it joins', (tester) async {
      final households = FakeHouseholdRepository()
        ..redeemGate = Completer<void>();
      await _pump(tester, households: households);
      await _continue(tester);

      await tester.ensureVisible(find.text(joinLabel));
      await tester.tap(find.text(joinLabel));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      households.redeemGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HubScreen), findsOneWidget);
    });

    for (final error in [InviteError.used, InviteError.expired]) {
      testWidgets('${error.key} goes back to the code, with the error', (
        tester,
      ) async {
        final households = FakeHouseholdRepository()..redeemResult = error;
        await _pump(tester, households: households);
        await _continue(tester);

        await _tapText(tester, joinLabel);

        expect(_codeField, findsOneWidget);
        expect(_codeText(tester), 'K7QM X2PA');
        expect(find.text(inviteErrorText(error)), findsOneWidget);
      });
    }

    for (final (error, message) in [
      (InviteError.householdFull, householdFullMessage),
      (InviteError.demoMismatch, demoMismatchMessage),
      (InviteError.startDateOutOfRange, startDateExpiredMessage),
      (InviteError.noProfile, joinFailedMessage),
    ]) {
      testWidgets('${error.key} says "$message" and stays', (tester) async {
        final households = FakeHouseholdRepository()..redeemResult = error;
        await _pump(tester, households: households);
        await _continue(tester);

        await _tapText(tester, joinLabel);

        expect(_snackBar(tester), message);
        expect(find.text(joinLabel), findsOneWidget);
      });
    }

    test('the texts of the snackbars are those of the specification', () {
      expect(
        demoMismatchMessage,
        'Gli account demo e gli altri account non possono stare nella stessa '
        'casa.',
      );
      expect(alreadyMemberMessage, 'Fai già parte di una casa.');
      expect(
        joinFailedMessage,
        'Non è stato possibile entrare nella casa. Riprova.',
      );
    });

    for (final (name, error, message) in [
      ('without network', offline as Exception, noConnectionMessage),
      ('any other error', serverError, joinFailedMessage),
    ]) {
      testWidgets('$name says "$message" and stays', (tester) async {
        final households = FakeHouseholdRepository()..redeemThrows = error;
        await _pump(tester, households: households);
        await _continue(tester);

        await _tapText(tester, joinLabel);

        expect(_snackBar(tester), message);
        expect(find.text(joinLabel), findsOneWidget);
      });
    }

    testWidgets('already_member says so, reads the state again and goes on', (
      tester,
    ) async {
      final households = FakeHouseholdRepository()
        ..redeemResult = InviteError.alreadyMember;
      final pumped = await _pump(tester, households: households);
      await _continue(tester);
      pumped.accounts.status = noHouseholdAccount.copyWith(hasMember: true);
      final reads = pumped.accounts.reads;

      await _tapText(tester, joinLabel);

      expect(_snackBar(tester), alreadyMemberMessage);
      expect(pumped.accounts.reads, reads + 1);
      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('back returns to the code, with the code', (tester) async {
      await _pump(tester);
      await _continue(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(_codeField, findsOneWidget);
      expect(_codeText(tester), 'K7QM X2PA');
    });

    testWidgets('the layout follows the board', (tester) async {
      await _pump(tester);
      await _continue(tester);

      final card = find
          .ancestor(
            of: find.text('Casa di prova'),
            matching: find.byType(DecoratedBox),
          )
          .first;
      final decoration =
          tester.widget<DecoratedBox>(card).decoration as BoxDecoration;
      final scheme = Theme.of(tester.element(card)).colorScheme;
      expect(decoration.color, scheme.surfaceContainerLow);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadii.card));
      final box = find
          .ancestor(
            of: find.byIcon(Symbols.info_rounded),
            matching: find.byType(DecoratedBox),
          )
          .first;
      final boxDecoration =
          tester.widget<DecoratedBox>(box).decoration as BoxDecoration;
      expect(boxDecoration.color, scheme.surfaceContainerHigh);
      expect(boxDecoration.borderRadius, BorderRadius.circular(AppRadii.inner));
      final join = find.ancestor(
        of: find.text(joinLabel),
        matching: find.byType(FilledButton),
      );
      expect(tester.getSize(join).height, JoinHouseholdScreen.buttonHeight);
      expect(tester.getBottomLeft(join).dy, 844 - AppSpacing.xl);
    });

    group('with the text at 200%', () {
      for (final size in [const Size(390, 844), const Size(320, 640)]) {
        testWidgets('cuts nothing at $size, and "Entra" is reachable', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = AppTextScale.max;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pump(tester, window: size);
          await _continue(tester);

          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text(joinLabel));
          await tester.pumpAndSettle();
          expect(find.text(joinLabel).hitTestable(), findsOneWidget);
        });
      }
    });
  });

  group('the pending invite', () {
    testWidgets('A7 is skipped: A10 asks the preview with the token', (
      tester,
    ) async {
      final pumped = await _pump(tester, pendingInvite: true);

      expect(find.byType(JoinHouseholdScreen), findsOneWidget);
      expect(pumped.households.previews.single.token, inventedToken);
      expect(pumped.households.previews.single.code, isNull);
      expect(find.text('Casa di prova'), findsOneWidget);
    });

    testWidgets('"Entra" uses the token, and the invite goes', (tester) async {
      final pumped = await _pump(tester, pendingInvite: true);

      await _tapText(tester, joinLabel);

      expect(pumped.households.redeems.single.token, inventedToken);
      expect(pumped.households.redeems.single.code, isNull);
      expect(pumped.store.values[StartupGate.pendingInviteKey], isNull);
      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('a failed preview shows the code of the link with the error', (
      tester,
    ) async {
      final households = FakeHouseholdRepository()
        ..previewResult = (preview: null, error: InviteError.expired);
      await _pump(tester, households: households, pendingInvite: true);

      expect(_codeText(tester), 'K7QM X2PA');
      expect(find.text(inviteErrorText(InviteError.expired)), findsOneWidget);
    });

    testWidgets('back from the preview shows the code; again, A7, and the '
        'invite goes', (tester) async {
      final pumped = await _pump(tester, pendingInvite: true);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_codeText(tester), 'K7QM X2PA');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);
      expect(pumped.store.values[StartupGate.pendingInviteKey], isNull);
    });

    testWidgets('a code written by hand is asked by code', (tester) async {
      final households = FakeHouseholdRepository()
        ..previewResult = (preview: null, error: InviteError.used);
      await _pump(tester, households: households, pendingInvite: true);
      households.previewResult = _preview();

      await _continue(tester, 'P4RW 9HTC');

      expect(households.previews.last.code, 'P4RW9HTC');
      expect(households.previews.last.token, isNull);
    });
  });

  group('the invite link', () {
    testWidgets('at a cold start opens A10 with the invite', (tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = _link;
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final households = FakeHouseholdRepository();
      final router = await pumpApp(
        tester,
        accounts: FakeAccountRepository(status: noHouseholdAccount),
        households: households,
        now: _now,
      );

      expect(router.location, '/household/join');
      expect(households.previews.single.token, inventedToken);
      expect(find.text('Casa di prova'), findsOneWidget);
    });

    testWidgets('with the app open on A7 opens A10', (tester) async {
      final households = FakeHouseholdRepository();
      final router = await pumpApp(
        tester,
        location: '/household',
        accounts: FakeAccountRepository(status: noHouseholdAccount),
        households: households,
        now: _now,
      );
      expect(find.byType(HouseholdChoiceScreen), findsOneWidget);

      await _openLink(tester, _link);

      expect(router.location, '/household/join');
      expect(households.previews.single.token, inventedToken);
    });

    testWidgets('before the sign-in waits for A2 and A3, then A10', (
      tester,
    ) async {
      final households = FakeHouseholdRepository();
      final router = await pumpApp(
        tester,
        auth: FakeAuthRepository(signedIn: false),
        accounts: FakeAccountRepository(status: newAccount),
        households: households,
        now: _now,
      );
      await _openLink(tester, _link);
      expect(find.byType(SignInScreen), findsOneWidget);

      await tester.tap(find.text('Continua con Google'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await _tapText(tester, 'Continua');

      expect(router.location, '/household/join');
      expect(households.previews.single.token, inventedToken);
    });

    testWidgets('with a household goes to the hub, which says so', (
      tester,
    ) async {
      final store = MemoryLocalStore();
      final router = await pumpApp(tester, store: store);

      await _openLink(tester, _link);

      expect(router.location, '/');
      expect(
        _snackBar(tester),
        'Fai già parte di una casa: un account può stare in una sola casa.',
      );
      expect(store.values[StartupGate.pendingInviteKey], isNull);
    });

    testWidgets('a link not valid is ignored', (tester) async {
      final store = MemoryLocalStore();
      final router = await pumpApp(
        tester,
        location: '/household',
        accounts: FakeAccountRepository(status: noHouseholdAccount),
        store: store,
      );

      await _openLink(tester, 'https://example.pages.dev/invite/#t=x&c=y');

      expect(router.location, '/household');
      expect(store.values[StartupGate.pendingInviteKey], isNull);
    });

    testWidgets('is never a destination', (tester) async {
      final router = await pumpApp(
        tester,
        accounts: FakeAccountRepository(status: noHouseholdAccount),
        now: _now,
      );
      await _openLink(tester, _link);
      expect(GoRouterStateFinder.queryOf(router), isNot(contains('invite')));

      await _tapText(tester, joinLabel);

      expect(router.location, '/');
    });

    testWidgets('of the dev app goes under /dev/invite only', (tester) async {
      final households = FakeHouseholdRepository();
      final router = await pumpApp(
        tester,
        location: '/household',
        accounts: FakeAccountRepository(status: noHouseholdAccount),
        households: households,
        flavor: 'dev',
        now: _now,
      );

      await _openLink(tester, _link);
      expect(router.location, '/household');

      await _openLink(
        tester,
        'https://example.pages.dev/dev/invite/#t=$inventedToken&c=K7QMX2PA',
      );
      expect(router.location, '/household/join');
    });
  });
}

/// Delivers [link] as Android does with the app open: a new route from the
/// platform.
Future<void> _openLink(WidgetTester tester, String link) async {
  const codec = JSONMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': link, 'state': null}),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

/// The query of the location the router shows.
abstract final class GoRouterStateFinder {
  static String queryOf(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.query;
}
