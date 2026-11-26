@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/features/household/create_household_screen.dart';
import 'package:homemade/features/household/household_choice_screen.dart';
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

/// Closes the keyboard: no cursor in the pictures.
void _unfocus() => FocusManager.instance.primaryFocus?.unfocus();

/// Create or join a household (A7) and create a household (A8) in Teal
/// dark with the text at 100% (`docs/spec/accesso.md`, sections 5 and 6),
/// with invented data: Anna, "Casa di prova", a fixed today, 15 March 2031.
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
}
