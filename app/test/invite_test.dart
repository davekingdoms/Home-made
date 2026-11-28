import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/design/qr_code_box.dart';
import 'package:homemade/features/household/create_household_screen.dart';
import 'package:homemade/features/household/household_choice_screen.dart';
import 'package:homemade/features/household/household_repository.dart';
import 'package:homemade/features/household/invite_screen.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/text_scale.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/design_harness.dart';
import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

/// An invented today: a Saturday in the middle of March 2031.
final _now = DateTime(2031, 3, 15, 10, 30);

/// The link of the first invite the fake makes.
const _link = 'https://example.pages.dev/invite/#t=$inventedToken&c=K7QMX2PA';

/// What a pumped A9 leaves around it.
typedef _Pumped = ({
  FakeHouseholdRepository households,
  List<String> shared,
  List<String> copied,
});

/// Pumps A7 for an account without a household on [now], then creates the
/// household from A8: the app shows A9, as after a real "Crea".
Future<_Pumped> _pump(
  WidgetTester tester, {
  FakeHouseholdRepository? households,
  DateTime? now,
  Size window = const Size(390, 844),
  double textScale = 1,
}) async {
  final repository = households ?? FakeHouseholdRepository();
  final shared = <String>[];
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add(
          (call.arguments as Map<Object?, Object?>)['text']! as String,
        );
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await pumpApp(
    tester,
    location: '/household',
    accounts: FakeAccountRepository(status: noHouseholdAccount),
    households: repository,
    now: now ?? _now,
    window: window,
    sharedTexts: shared,
  );
  await tester.tap(find.text(createCardTitle));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, householdNameLabel),
    'Casa di prova',
  );
  await tester.pump();
  await tester.tap(find.text(createHouseholdLabel));
  await tester.pumpAndSettle();
  return (households: repository, shared: shared, copied: copied);
}

Finder get _labelField => find.widgetWithText(TextField, inviteLabelLabel);

/// Writes [label], if any, and taps "Crea l'invito".
Future<void> _createInvite(WidgetTester tester, {String? label}) async {
  if (label != null) {
    await tester.enterText(_labelField, label);
    await tester.pump();
  }
  await _tapText(tester, createInviteLabel);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

String? _snackBar(WidgetTester tester) {
  final bar = find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(Text),
  );
  return bar.evaluate().isEmpty ? null : tester.widget<Text>(bar.first).data;
}

void main() {
  setUpAll(loadAppFonts);

  group('A9 after "Crea"', () {
    testWidgets('opens with the field and "Crea l\'invito", no invite yet', (
      tester,
    ) async {
      final pumped = await _pump(tester);

      expect(find.byType(InviteScreen), findsOneWidget);
      expect(find.text(inviteTitle), findsOneWidget);
      expect(find.text(invitePhrase), findsOneWidget);
      expect(find.text(inviteLabelHelper), findsOneWidget);
      expect(find.text(createInviteLabel), findsOneWidget);
      expect(find.text(inviteLaterLabel), findsOneWidget);
      expect(find.byType(QrCodeBox), findsNothing);
      expect(find.text(openInvitesTitle), findsNothing);
      // Nothing is created by opening A9: it would hold a place.
      expect(pumped.households.inviteLabels, isEmpty);
      expect(pumped.households.contextReads, 1);
    });

    testWidgets('has no back arrow in the bar', (tester) async {
      await _pump(tester);

      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('"Più tardi" goes on to the hub', (tester) async {
      await _pump(tester);

      await _tapText(tester, inviteLaterLabel);

      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('back goes on to the hub too', (tester) async {
      await _pump(tester);

      await systemBack(tester);

      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('"Crea l\'invito" sends the label without spaces', (
      tester,
    ) async {
      final pumped = await _pump(tester);

      await _createInvite(tester, label: '  Bruno  ');

      expect(pumped.households.inviteLabels, ['Bruno']);
    });

    testWidgets('without a label, sends none', (tester) async {
      final pumped = await _pump(tester);

      await _createInvite(tester, label: '   ');

      expect(pumped.households.inviteLabels, [null]);
    });

    testWidgets('the label starts with a capital and takes 40 characters', (
      tester,
    ) async {
      await _pump(tester);

      final field = tester.widget<TextField>(_labelField);
      expect(field.textCapitalization, TextCapitalization.sentences);
      await tester.enterText(_labelField, 'a' * 50);
      await tester.pump();
      expect(tester.widget<TextField>(_labelField).controller!.text, 'a' * 40);
    });

    testWidgets('the card shows QR, code and expiry', (tester) async {
      await _pump(tester);

      await _createInvite(tester, label: 'Bruno');

      expect(find.byType(QrCodeBox), findsOneWidget);
      expect(tester.widget<QrCodeBox>(find.byType(QrCodeBox)).data, _link);
      expect(find.text('K7QM X2PA'), findsOneWidget);
      expect(find.text('Scade il 22 marzo'), findsOneWidget);
      expect(find.text(copyCodeLabel), findsOneWidget);
      expect(find.text(copyLinkLabel), findsOneWidget);
      expect(find.text(shareInviteLabel), findsOneWidget);
      expect(find.text(inviteAnotherLabel), findsOneWidget);
      expect(find.text(createInviteLabel), findsNothing);
      // The field keeps the label and cannot change any more.
      final field = tester.widget<TextField>(_labelField);
      expect(field.readOnly, isTrue);
      expect(field.controller!.text, 'Bruno');
    });

    testWidgets('the screen reader hears the code one character at a time', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      await _createInvite(tester);

      expect(
        find.bySemanticsLabel('$inviteCodeCaption: K 7 Q M, X 2 P A'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(inviteQrLabel), findsOneWidget);
      expect(find.bySemanticsLabel(inviteRegionLabel), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the expiry has the year only when it is another', (
      tester,
    ) async {
      await _pump(tester, now: DateTime(2031, 12, 28, 10));

      await _createInvite(tester);

      expect(find.text('Scade il 4 gennaio 2032'), findsOneWidget);
    });

    testWidgets('"Copia codice" copies the code, says so, and "Più tardi" '
        'becomes "Continua"', (tester) async {
      final pumped = await _pump(tester);
      await _createInvite(tester);

      await _tapText(tester, copyCodeLabel);

      expect(pumped.copied, ['K7QM X2PA']);
      expect(_snackBar(tester), codeCopiedMessage);
      expect(find.text(inviteContinueLabel), findsOneWidget);
      expect(find.text(inviteLaterLabel), findsNothing);
    });

    testWidgets('"Copia link" copies the link', (tester) async {
      final pumped = await _pump(tester);
      await _createInvite(tester);

      await _tapText(tester, copyLinkLabel);

      expect(pumped.copied, [_link]);
      expect(_snackBar(tester), linkCopiedMessage);
      expect(find.text(inviteContinueLabel), findsOneWidget);
    });

    testWidgets('"Condividi l\'invito" hands the text to the share sheet', (
      tester,
    ) async {
      final pumped = await _pump(tester);
      await _createInvite(tester, label: 'Bruno');

      await _tapText(tester, shareInviteLabel);

      const text =
          'Ti invito nella casa «Casa di prova» su Home-made.\n'
          'Apri questo link sul telefono: $_link\n'
          "Oppure, nell'app, tocca «Ho un invito» e scrivi il codice "
          'K7QM X2PA.\n'
          "L'invito vale fino al 22 marzo.";
      expect(pumped.shared, [text]);
      expect(find.text(inviteContinueLabel), findsOneWidget);
    });

    testWidgets('without a share or a copy it stays "Più tardi"', (
      tester,
    ) async {
      await _pump(tester);
      await _createInvite(tester);

      expect(find.text(inviteLaterLabel), findsOneWidget);
    });

    testWidgets('"Continua" goes on to the hub', (tester) async {
      await _pump(tester);
      await _createInvite(tester);
      await _tapText(tester, copyCodeLabel);
      // The snackbar would take the tap.
      ScaffoldMessenger.of(tester.element(find.byType(InviteScreen)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();

      await _tapText(tester, inviteContinueLabel);

      expect(find.byType(HubScreen), findsOneWidget);
    });

    testWidgets('"Invita un\'altra persona" moves the invite among the open '
        'ones and empties the field', (tester) async {
      final pumped = await _pump(tester);
      await _createInvite(tester, label: 'Bruno');
      await _tapText(tester, copyLinkLabel);

      await _tapText(tester, inviteAnotherLabel);

      expect(find.text(openInvitesTitle), findsOneWidget);
      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('Scade il 22 marzo'), findsOneWidget);
      expect(find.byType(QrCodeBox), findsNothing);
      expect(tester.widget<TextField>(_labelField).controller!.text, isEmpty);
      expect(tester.widget<TextField>(_labelField).readOnly, isFalse);
      // A share or a copy of this visit keeps "Continua".
      expect(find.text(inviteContinueLabel), findsOneWidget);

      await _createInvite(tester, label: 'Carla');
      expect(pumped.households.inviteLabels, ['Bruno', 'Carla']);
      expect(find.text('P4RW 9HTC'), findsOneWidget);
    });

    testWidgets('the open invites come first, the latest at the top, with '
        '"Invito senza nome"', (tester) async {
      final households = FakeHouseholdRepository()
        ..openInvites = [
          OpenInvite(
            id: 'invite-2',
            expiresAt: DateTime(2031, 3, 20, 9),
            createdAt: DateTime(2031, 3, 13, 9),
          ),
          OpenInvite(
            id: 'invite-1',
            label: 'Bruno',
            expiresAt: DateTime(2031, 3, 18, 9),
            createdAt: DateTime(2031, 3, 11, 9),
          ),
        ];
      await _pump(tester, households: households);

      expect(find.text(openInvitesTitle), findsOneWidget);
      final unnamed = tester.getTopLeft(find.text(unnamedInvite));
      final bruno = tester.getTopLeft(find.text('Bruno'));
      expect(unnamed.dy, lessThan(bruno.dy));
      expect(find.text('Scade il 20 marzo'), findsOneWidget);
      expect(find.text('Scade il 18 marzo'), findsOneWidget);
    });

    testWidgets('the rows of the open invites follow the board', (
      tester,
    ) async {
      final households = FakeHouseholdRepository()
        ..openInvites = [
          OpenInvite(
            id: 'invite-1',
            label: 'Bruno',
            expiresAt: DateTime(2031, 3, 22, 9),
            createdAt: DateTime(2031, 3, 15, 9),
          ),
        ];
      await _pump(tester, households: households);

      final row = find
          .ancestor(of: find.text('Bruno'), matching: find.byType(Container))
          .first;
      final decoration =
          tester.widget<Container>(row).decoration! as BoxDecoration;
      final scheme = Theme.of(tester.element(row)).colorScheme;
      expect(decoration.color, scheme.surfaceContainerHigh);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadii.inner));
      expect(
        tester.getSize(row).height,
        greaterThanOrEqualTo(InviteScreen.openInviteMinHeight),
      );
    });

    testWidgets('a failed read of the invites leaves the list out, and '
        '"Crea l\'invito" reads them again', (tester) async {
      final households = FakeHouseholdRepository()..contextError = offline;
      await _pump(tester, households: households);
      expect(find.text(openInvitesTitle), findsNothing);

      households.contextError = null;
      await _createInvite(tester);

      expect(households.contextReads, 2);
      expect(find.byType(QrCodeBox), findsOneWidget);
    });

    testWidgets('shows an indicator while it creates', (tester) async {
      final households = FakeHouseholdRepository()
        ..inviteGate = Completer<void>();
      await _pump(tester, households: households);

      await tester.tap(find.text(createInviteLabel));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      households.inviteGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(QrCodeBox), findsOneWidget);
    });

    for (final (name, error, message) in [
      ('without network', offline as Exception, noConnectionMessage),
      (
        'household_full',
        householdError('household_full'),
        householdFullMessage,
      ),
      ('not_member', householdError('not_member'), createInviteFailedMessage),
      ('any other error', serverError, createInviteFailedMessage),
    ]) {
      testWidgets('$name says "$message" and stays', (tester) async {
        final households = FakeHouseholdRepository()..inviteError = error;
        await _pump(tester, households: households);

        await _createInvite(tester);

        expect(_snackBar(tester), message);
        expect(find.byType(QrCodeBox), findsNothing);
        expect(find.text(createInviteLabel), findsOneWidget);
      });
    }

    testWidgets('the layout follows the board', (tester) async {
      await _pump(tester);
      await _createInvite(tester, label: 'Bruno');

      final bar = tester.getSize(find.byType(AppBar));
      expect(bar.height, AppSizes.topBarHeight);
      final card = find
          .ancestor(
            of: find.byType(QrCodeBox),
            matching: find.byType(DecoratedBox),
          )
          .first;
      final decoration =
          tester.widget<DecoratedBox>(card).decoration as BoxDecoration;
      final scheme = Theme.of(tester.element(card)).colorScheme;
      expect(decoration.color, scheme.surfaceContainerLow);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadii.card));
      expect(tester.getSize(find.byType(QrCodeBox)), const Size.square(112));
      final share = find.ancestor(
        of: find.text(shareInviteLabel),
        matching: find.byType(FilledButton),
      );
      expect(tester.getSize(share).height, InviteScreen.mainButtonHeight);
      // The visible button, inside its touch target.
      final copy = find
          .ancestor(
            of: find.text(copyCodeLabel),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.getSize(copy).height, InviteScreen.copyButtonHeight);
      final later = find.ancestor(
        of: find.text(inviteLaterLabel),
        matching: find.byType(OutlinedButton),
      );
      expect(tester.getSize(later).height, AppSizes.buttonHeight);
      // "Più tardi" at the bottom, 24 above the edge.
      expect(tester.getBottomLeft(later).dy, 844 - AppSpacing.xl);
    });

    group('with the text at 200%', () {
      for (final size in [const Size(390, 844), const Size(320, 640)]) {
        testWidgets('cuts nothing at $size, and the buttons are reachable', (
          tester,
        ) async {
          await _pump(tester, window: size, textScale: AppTextScale.max);
          await _createInvite(tester, label: 'Bruno');

          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text(inviteLaterLabel));
          await tester.pumpAndSettle();
          expect(find.text(inviteLaterLabel).hitTestable(), findsOneWidget);
        });
      }
    });
  });
}
