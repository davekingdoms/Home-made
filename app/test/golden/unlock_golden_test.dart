@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/features/auth/unlock_screen.dart';
import 'package:homemade/theme/app_theme.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/design_harness.dart';

/// Windows, in dp: a phone and an expanded window, where the column of A1
/// is centred.
const _windows = {'phone': Size(390, 844), 'expanded': Size(1280, 800)};

/// The unlock (A1) after a cancelled request, in Teal dark with the text at
/// 100% (`docs/spec/accesso.md`, section 2). The request itself is drawn by
/// the system.
///
/// The reference pictures are drawn on Linux, by the CI: to regenerate them,
/// add the `update-goldens` label to the pull request or run the "Update
/// goldens" workflow on the branch (see CLAUDE.md, section CI).
void main() {
  setUpAll(loadAppFonts);

  for (final MapEntry(key: name, value: window) in _windows.entries) {
    testWidgets('A1, $name window, Teal dark', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = window;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(AppPalette.teal, Brightness.dark),
          locale: const Locale('it'),
          supportedLocales: const [Locale('it')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: UnlockScreen(onUnlock: () {}, onSignOut: () {}),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(UnlockScreen),
        matchesGoldenFile('goldens/unlock_${name}_dark.png'),
      );
    });
  }
}
