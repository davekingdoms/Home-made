@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/features/finance/finance_shell.dart';
import 'package:homemade/theme/app_theme.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/design_harness.dart';

/// Tablet windows, in dp: medium in portrait, expanded in landscape.
const _windows = {'medium': Size(800, 1280), 'expanded': Size(1280, 800)};

/// The Finance shell in tablet format, with the side bar and the placeholder
/// tabs, in Teal light and dark (`docs/spec/navigazione.md`, section 5).
///
/// The reference pictures are drawn on Linux, by the CI: to regenerate them,
/// add the `update-goldens` label to the pull request or run the "Update
/// goldens" workflow on the branch (see CLAUDE.md, section CI).
void main() {
  setUpAll(loadAppFonts);

  for (final MapEntry(key: name, value: window) in _windows.entries) {
    for (final brightness in Brightness.values) {
      testWidgets('Finance shell, $name window, Teal ${brightness.name}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.physicalSize = window;
        addTearDown(tester.view.resetPhysicalSize);
        // The tests draw shadows as solid black outlines; the tablet draws
        // the real ones.
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);

        final rootKey = GlobalKey<NavigatorState>();
        final router = GoRouter(
          navigatorKey: rootKey,
          initialLocation: '/finance/summary',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const SizedBox(),
              routes: [financeRoute(rootKey)],
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(AppPalette.teal, brightness),
            locale: const Locale('it'),
            supportedLocales: const [Locale('it')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            routerConfig: router,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NavigationRail), findsOneWidget);
        await expectLater(
          find.byType(FinanceShell),
          matchesGoldenFile(
            'goldens/finance_shell_${name}_${brightness.name}.png',
          ),
        );
      });
    }
  }
}
