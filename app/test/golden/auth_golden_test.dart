@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/welcome_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/design_harness.dart';
import '../helpers/fake_auth_repository.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// Windows, in dp: a phone and an expanded window, where the column is
/// centred.
const _phone = Size(390, 844);
const _expanded = Size(1280, 800);

/// The configuration on `dev`, with the checkbox of the demo accounts.
const _devConfig = AppConfig(
  appEnv: 'dev',
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'placeholder',
  googleWebClientId: 'placeholder.apps.googleusercontent.com',
  pagesBaseUrl: 'https://example.pages.dev',
);

/// A window [size] dp wide and high, one pixel per dp, in the dark theme:
/// the app follows the system and starts in Teal.
void _darkWindow(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  setWindow(tester, size);
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

/// Sign-in (A2) and first access (A3) in Teal dark with the text at 100%
/// (`docs/spec/accesso.md`, sections 3 and 4), with invented data: Anna,
/// without a photo.
///
/// The reference pictures are drawn on Linux, by the CI: to regenerate them,
/// add the `update-goldens` label to the pull request or run the "Update
/// goldens" workflow on the branch (see CLAUDE.md, section CI).
void main() {
  setUpAll(loadAppFonts);

  group('A2', () {
    for (final MapEntry(key: name, value: window) in {
      'phone': _phone,
      'expanded': _expanded,
    }.entries) {
      testWidgets('$name window', (tester) async {
        _darkWindow(tester, window);
        await pumpApp(
          tester,
          location: '/sign-in',
          auth: FakeAuthRepository(signedIn: false),
        );

        await expectLater(
          find.byType(SignInScreen),
          matchesGoldenFile('goldens/sign_in_${name}_dark.png'),
        );
      });
    }

    testWidgets('in the light theme, phone window', (tester) async {
      _darkWindow(tester, _phone);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await pumpApp(
        tester,
        location: '/sign-in',
        auth: FakeAuthRepository(signedIn: false),
      );

      await expectLater(
        find.byType(SignInScreen),
        matchesGoldenFile('goldens/sign_in_phone_light.png'),
      );
    });

    testWidgets('after a lost session, phone window', (tester) async {
      _darkWindow(tester, _phone);
      final auth = FakeAuthRepository();
      await pumpApp(tester, auth: auth);
      auth.loseSession();
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(SignInScreen),
        matchesGoldenFile('goldens/sign_in_session_lost_phone_dark.png'),
      );
    });

    testWidgets('on dev, with "Modalità demo", phone window', (tester) async {
      _darkWindow(tester, _phone);
      await pumpApp(
        tester,
        location: '/sign-in',
        config: _devConfig,
        auth: FakeAuthRepository(signedIn: false),
      );

      await expectLater(
        find.byType(SignInScreen),
        matchesGoldenFile('goldens/sign_in_demo_phone_dark.png'),
      );
    });
  });

  group('A3', () {
    for (final MapEntry(key: name, value: window) in {
      'phone': _phone,
      'expanded': _expanded,
    }.entries) {
      testWidgets('whole, checkbox ticked, $name window', (tester) async {
        _darkWindow(tester, window);
        await pumpApp(
          tester,
          location: '/welcome',
          accounts: FakeAccountRepository(status: newAccount),
        );
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(WelcomeScreen),
          matchesGoldenFile('goldens/welcome_${name}_dark.png'),
        );
      });
    }

    testWidgets('notice updated, phone window', (tester) async {
      _darkWindow(tester, _phone);
      await pumpApp(
        tester,
        location: '/welcome',
        accounts: FakeAccountRepository(status: oldNoticeAccount),
      );

      await expectLater(
        find.byType(WelcomeScreen),
        matchesGoldenFile('goldens/welcome_notice_updated_phone_dark.png'),
      );
    });
  });
}
