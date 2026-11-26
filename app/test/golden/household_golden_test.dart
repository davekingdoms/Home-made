@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/features/household/create_household_screen.dart';
import 'package:homemade/features/household/household_choice_screen.dart';
import 'package:homemade/features/household/household_repository.dart';
import 'package:homemade/features/household/invite_screen.dart';
import 'package:homemade/features/household/join_household_screen.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/design_harness.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// Windows, in dp: a phone and an expanded window, where the column is
/// centred.
const _phone = Size(390, 844);
const _expanded = Size(1280, 800);

/// A fixed today, invented: the start date proposed is "1° marzo 2031".
final _now = DateTime(2031, 3, 15, 10);

/// Anna, past first access, without a household.
const _anna = AccountStatus(
  hasProfile: true,
  noticeVersion: privacyNoticeVersion,
  hasMember: false,
  displayName: 'Anna',
);

/// A window [size] dp wide and high, one pixel per dp, in [brightness]:
/// the app follows the system and starts in Teal.
void _window(
  WidgetTester tester,
  Size size, {
  Brightness brightness = Brightness.dark,
}) {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  setWindow(tester, size);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

/// Pumps A7 for Anna on [_now].
Future<void> _pumpChoice(WidgetTester tester) async {
  await pumpApp(
    tester,
    location: '/household',
    accounts: FakeAccountRepository(status: _anna),
    now: _now,
  );
}

/// Opens A8 from A7, as the app does, and writes the name of the household.
Future<void> _pumpCreate(WidgetTester tester) async {
  await _pumpChoice(tester);
  await tester.tap(find.text(createCardTitle));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, householdNameLabel),
    'Casa di prova',
  );
  _unfocus();
  await tester.pumpAndSettle();
}

/// Creates "Casa di prova" from A8: the app shows A9, as after a real
/// "Crea".
Future<void> _pumpInvite(WidgetTester tester) async {
  await _pumpCreate(tester);
  await _tap(tester, createHouseholdLabel);
}

/// Writes [label] and creates the invite.
Future<void> _createInvite(WidgetTester tester, String label) async {
  await tester.enterText(
    find.widgetWithText(TextField, inviteLabelLabel),
    label,
  );
  _unfocus();
  await tester.pumpAndSettle();
  await _tap(tester, createInviteLabel);
}

/// Opens A10 from A7 and asks the preview of the code, which [households]
/// answers.
Future<void> _pumpJoin(
  WidgetTester tester,
  FakeHouseholdRepository households,
) async {
  await pumpApp(
    tester,
    location: '/household',
    accounts: FakeAccountRepository(status: _carla),
    households: households,
    now: _now,
  );
  await _tap(tester, joinCardTitle);
  await tester.enterText(
    find.widgetWithText(TextField, inviteCodeLabel),
    'K7QM X2PA',
  );
  _unfocus();
  await tester.pumpAndSettle();
  await _tap(tester, joinContinueLabel);
  _unfocus();
  await tester.pumpAndSettle();
}

/// Carla, past first access, without a household.
const _carla = AccountStatus(
  hasProfile: true,
  noticeVersion: privacyNoticeVersion,
  hasMember: false,
  displayName: 'Carla',
);

/// The preview of "Casa di prova" of Anna and Bruno, started on [start].
InvitePreviewResult _preview(DateTime start) => (
  preview: InvitePreview(
    householdName: 'Casa di prova',
    inviterName: 'Anna',
    memberNames: const ['Anna', 'Bruno'],
    householdStartDate: start,
  ),
  error: null,
);

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// Closes the keyboard: no cursor in the pictures.
void _unfocus() => FocusManager.instance.primaryFocus?.unfocus();

/// Create or join a household (A7), create a household (A8), invite (A9)
/// and join with an invite (A10) in Teal dark with the text at 100%
/// (`docs/spec/accesso.md`, sections 5–8), with invented data: Anna, Bruno
/// and Carla, "Casa di prova" started on 1 March 2031, a fixed today, 15
/// March 2031, invented codes and an invented link in the QR.
///
/// The reference pictures are drawn on Linux, by the CI: to regenerate them,
/// add the `update-goldens` label to the pull request or run the "Update
/// goldens" workflow on the branch (see CLAUDE.md, section CI).
void main() {
  setUpAll(loadAppFonts);

  group('A7', () {
    for (final MapEntry(key: name, value: window) in {
      'phone': _phone,
      'expanded': _expanded,
    }.entries) {
      testWidgets('$name window', (tester) async {
        _window(tester, window);
        await _pumpChoice(tester);

        await expectLater(
          find.byType(HouseholdChoiceScreen),
          matchesGoldenFile('goldens/household_choice_${name}_dark.png'),
        );
      });
    }

    testWidgets('in the light theme, phone window', (tester) async {
      _window(tester, _phone, brightness: Brightness.light);
      await _pumpChoice(tester);

      await expectLater(
        find.byType(HouseholdChoiceScreen),
        matchesGoldenFile('goldens/household_choice_phone_light.png'),
      );
    });
  });

  group('A8', () {
    for (final MapEntry(key: name, value: window) in {
      'phone': _phone,
      'expanded': _expanded,
    }.entries) {
      testWidgets('default start date, $name window', (tester) async {
        _window(tester, window);
        await _pumpCreate(tester);

        await expectLater(
          find.byType(CreateHouseholdScreen),
          matchesGoldenFile('goldens/create_household_${name}_dark.png'),
        );
      });
    }

    testWidgets('start date today, with the cash, phone window', (
      tester,
    ) async {
      _window(tester, _phone);
      await _pumpCreate(tester);
      await tester.tap(find.text(startDateLabel));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text('15'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, cashLabel),
        '12,50',
      );
      _unfocus();
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(CreateHouseholdScreen),
        matchesGoldenFile('goldens/create_household_today_phone_dark.png'),
      );
    });
  });

  group('A9', () {
    testWidgets('before the invite, phone window', (tester) async {
      _window(tester, _phone);
      await _pumpInvite(tester);

      await expectLater(
        find.byType(InviteScreen),
        matchesGoldenFile('goldens/invite_before_phone_dark.png'),
      );
    });

    for (final MapEntry(key: name, value: window) in {
      'phone': _phone,
      'expanded': _expanded,
    }.entries) {
      testWidgets('right after the invite, $name window', (tester) async {
        _window(tester, window);
        await _pumpInvite(tester);
        await _createInvite(tester, 'Bruno');

        await expectLater(
          find.byType(InviteScreen),
          matchesGoldenFile('goldens/invite_created_${name}_dark.png'),
        );
      });
    }

    testWidgets('second invite, with one open, phone window', (tester) async {
      _window(tester, _phone);
      await _pumpInvite(tester);
      await _createInvite(tester, 'Bruno');
      await _tap(tester, inviteAnotherLabel);
      await _createInvite(tester, 'Carla');

      await expectLater(
        find.byType(InviteScreen),
        matchesGoldenFile('goldens/invite_second_phone_dark.png'),
      );
    });
  });

  group('A10', () {
    testWidgets('code with an error, phone window', (tester) async {
      _window(tester, _phone);
      await _pumpJoin(
        tester,
        FakeHouseholdRepository()
          ..previewResult = (preview: null, error: InviteError.expired),
      );

      await expectLater(
        find.byType(JoinHouseholdScreen),
        matchesGoldenFile('goldens/join_code_error_phone_dark.png'),
      );
    });

    for (final MapEntry(key: name, value: window) in {
      'phone': _phone,
      'expanded': _expanded,
    }.entries) {
      testWidgets('preview of a household already started, $name window', (
        tester,
      ) async {
        _window(tester, window);
        await _pumpJoin(
          tester,
          FakeHouseholdRepository()
            ..previewResult = _preview(DateTime(2031, 3)),
        );

        await expectLater(
          find.byType(JoinHouseholdScreen),
          matchesGoldenFile('goldens/join_preview_${name}_dark.png'),
        );
      });
    }

    testWidgets('preview of a household not started, phone window', (
      tester,
    ) async {
      _window(tester, _phone);
      await _pumpJoin(
        tester,
        FakeHouseholdRepository()..previewResult = _preview(DateTime(2031, 4)),
      );

      await expectLater(
        find.byType(JoinHouseholdScreen),
        matchesGoldenFile('goldens/join_not_started_phone_dark.png'),
      );
    });
  });
}
