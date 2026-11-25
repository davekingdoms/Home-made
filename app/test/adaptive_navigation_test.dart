import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/core/display/orientation_policy.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/content_column.dart';
import 'package:homemade/design/section_rail.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/welcome_screen.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/text_scale.dart';
import 'package:homemade/theme/window_class.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

/// A medium window, as a tablet in portrait.
const _medium = Size(800, 1280);

/// An expanded window, as a tablet in landscape.
const _wide = Size(1280, 800);

Finder get _rail => find.byType(NavigationRail);
Finder get _bottomBar => find.byType(NavigationBar);

/// The "+" button inside the side bar.
Finder get _railButton =>
    find.descendant(of: _rail, matching: find.byType(FloatingActionButton));

/// The centred column of the screen on top.
Finder get _column => find
    .descendant(of: find.byType(ContentColumn), matching: find.byType(Column))
    .first;

/// Changes the window of the running app to [size] dp.
Future<void> _resize(WidgetTester tester, Size size) async {
  setWindow(tester, size);
  await tester.pumpAndSettle();
}

void main() {
  group('window class', () {
    test('changes at 600 and 840 dp', () {
      expect(WindowClass.fromWidth(0), WindowClass.compact);
      expect(WindowClass.fromWidth(599), WindowClass.compact);
      expect(WindowClass.fromWidth(599.9), WindowClass.compact);
      expect(WindowClass.fromWidth(600), WindowClass.medium);
      expect(WindowClass.fromWidth(839), WindowClass.medium);
      expect(WindowClass.fromWidth(839.9), WindowClass.medium);
      expect(WindowClass.fromWidth(840), WindowClass.expanded);
      expect(WindowClass.fromWidth(1280), WindowClass.expanded);
      expect(AppBreakpoints.medium, 600);
      expect(AppBreakpoints.expanded, 840);
    });

    test('only the compact class keeps the bottom bar', () {
      expect(WindowClass.compact.hasSideBar, isFalse);
      expect(WindowClass.medium.hasSideBar, isTrue);
      expect(WindowClass.expanded.hasSideBar, isTrue);
    });

    testWidgets('comes from the width of the window', (tester) async {
      const expected = [
        (599.0, WindowClass.compact),
        (600.0, WindowClass.medium),
        (839.0, WindowClass.medium),
        (840.0, WindowClass.expanded),
      ];
      for (final (width, windowClass) in expected) {
        setWindow(tester, Size(width, 400));
        late WindowClass found;
        await tester.pumpWidget(
          Builder(
            builder: (context) {
              found = WindowClass.of(context);
              return const SizedBox();
            },
          ),
        );
        expect(found, windowClass, reason: '$width dp');
      }
    });
  });

  group('Finance shell', () {
    for (final (width, sideBar) in const [
      (599.0, false),
      (600.0, true),
      (840.0, true),
    ]) {
      testWidgets('${sideBar ? 'side' : 'bottom'} bar at ${width.toInt()} dp', (
        tester,
      ) async {
        await pumpApp(
          tester,
          location: '/finance/summary',
          window: Size(width, 900),
        );

        expect(_rail, sideBar ? findsOneWidget : findsNothing);
        expect(_bottomBar, sideBar ? findsNothing : findsOneWidget);
        expect(find.text('C1 · Riepilogo'), findsOneWidget);
        // "‹ Finanze" stays in the top bar.
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Finanze'),
          ),
          findsOneWidget,
        );
        if (sideBar) {
          // The tabs and icons of the bottom bar, labels always visible.
          final rail = tester.widget<NavigationRail>(_rail);
          expect(rail.selectedIndex, 0);
          expect(rail.destinations, hasLength(4));
          for (final label in ['Riepilogo', 'Movimenti', 'Analisi', 'Conti']) {
            expect(
              find.descendant(of: _rail, matching: find.text(label)),
              findsOneWidget,
            );
          }
          final theme = Theme.of(tester.element(_rail));
          expect(
            theme.navigationRailTheme.labelType,
            NavigationRailLabelType.all,
          );
        }
      });
    }

    for (final window in [phoneWindow, _medium, _wide]) {
      testWidgets('"+" on Riepilogo and Movimenti only at ${window.width} dp', (
        tester,
      ) async {
        await pumpApp(tester, location: '/finance/summary', window: window);
        final sideBar = window.width >= AppBreakpoints.medium;
        Offset firstTab() => tester.getCenter(
          find.descendant(
            of: sideBar ? _rail : _bottomBar,
            matching: find.text('Riepilogo'),
          ),
        );
        final firstTabAt = firstTab();

        for (final (tab, hasButton) in const [
          ('Riepilogo', true),
          ('Movimenti', true),
          ('Analisi', false),
          ('Conti', false),
        ]) {
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
          expect(
            find.byType(FloatingActionButton),
            hasButton ? findsOneWidget : findsNothing,
            reason: tab,
          );
          if (sideBar) {
            // In the side bar, never at the bottom; without it the tabs
            // stay where they are.
            expect(_railButton, hasButton ? findsOneWidget : findsNothing);
            expect(firstTab(), firstTabAt, reason: tab);
          }
        }
      });
    }

    testWidgets('the "+" of the side bar opens F1', (tester) async {
      await pumpApp(tester, location: '/finance/transactions', window: _wide);
      await tester.tap(_railButton);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('F1 · Menu "+"'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('each tab of the side bar keeps its place', (tester) async {
      final router = await pumpApp(
        tester,
        location: '/finance/summary',
        window: _medium,
      );
      const tabs = {
        'Movimenti': '/finance/transactions',
        'Analisi': '/finance/analytics',
        'Conti': '/finance/accounts',
        'Riepilogo': '/finance/summary',
      };
      for (final (index, tab) in tabs.entries.indexed) {
        await tester.tap(
          find.descendant(of: _rail, matching: find.text(tab.key)),
        );
        await tester.pumpAndSettle();
        expect(router.location, tab.value);
        expect(
          tester.widget<NavigationRail>(_rail).selectedIndex,
          (index + 1) % 4,
        );
      }
    });

    testWidgets('tapping the current tab of the side bar keeps it', (
      tester,
    ) async {
      final router = await pumpApp(
        tester,
        location: '/finance/analytics',
        window: _wide,
      );
      await tester.tap(
        find.descendant(of: _rail, matching: find.text('Analisi')),
      );
      await tester.pumpAndSettle();

      expect(router.location, '/finance/analytics');
      expect(find.text('G1 · Analisi'), findsOneWidget);
    });

    testWidgets('back goes to Riepilogo, then to the hub', (tester) async {
      final router = await pumpApp(tester, window: _wide);
      await tester.tap(find.text('Finanze'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movimenti'));
      await tester.pumpAndSettle();
      expect(find.text('D1 · Movimenti'), findsOneWidget);

      await systemBack(tester);
      expect(find.text('C1 · Riepilogo'), findsOneWidget);
      expect(router.location, '/finance/summary');

      await systemBack(tester);
      expect(find.byType(HubScreen), findsOneWidget);
      expect(router.location, '/');
    });

    testWidgets('a detail covers the side bar, and back returns to the tab', (
      tester,
    ) async {
      final router = await pumpApp(
        tester,
        location: '/finance/accounts',
        window: _wide,
      );
      await tester.tap(
        find.byKey(const ValueKey('open-H2-/finance/accounts/$exampleId')),
      );
      await tester.pumpAndSettle();
      expect(find.text('H2 · Dettaglio conto'), findsOneWidget);
      expect(_rail, findsNothing);

      await systemBack(tester);
      expect(router.location, '/finance/accounts');
      expect(_rail, findsOneWidget);
    });
  });

  group('state kept when the window changes class', () {
    /// The shell of the tabs and the navigators of the tabs, also under a
    /// detail.
    List<State> shellStates(WidgetTester tester) {
      final shell = find.byType(StatefulNavigationShell, skipOffstage: false);
      return [
        tester.state(shell),
        ...tester.stateList<NavigatorState>(
          find.descendant(
            of: shell,
            matching: find.byType(Navigator, skipOffstage: false),
          ),
        ),
      ];
    }

    void expectSameStates(List<State> before, List<State> after) {
      expect(after, hasLength(before.length));
      for (final (index, state) in after.indexed) {
        expect(identical(state, before[index]), isTrue, reason: '$state');
      }
    }

    testWidgets('H2 over Conti stays open, and back returns to Conti', (
      tester,
    ) async {
      final router = await pumpApp(
        tester,
        location: '/finance/summary',
        window: const Size(400, 800),
      );
      await tester.tap(find.text('Conti'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('open-H2-/finance/accounts/$exampleId')),
      );
      await tester.pumpAndSettle();
      expect(find.text('H2 · Dettaglio conto'), findsOneWidget);
      final states = shellStates(tester);

      await _resize(tester, const Size(900, 800));
      expect(find.text('H2 · Dettaglio conto'), findsOneWidget);
      expect(router.location, '/finance/accounts/$exampleId');
      expect(find.byType(NavigationRail, skipOffstage: false), findsOneWidget);

      await _resize(tester, const Size(400, 800));
      expect(find.text('H2 · Dettaglio conto'), findsOneWidget);
      expectSameStates(states, shellStates(tester));

      await systemBack(tester);
      expect(router.location, '/finance/accounts');
      expect(find.text('H1 · I tuoi conti'), findsOneWidget);
      expect(tester.widget<NavigationBar>(_bottomBar).selectedIndex, 3);
    });

    testWidgets('the Analisi tab stays selected', (tester) async {
      final router = await pumpApp(
        tester,
        location: '/finance/summary',
        window: const Size(400, 800),
      );
      await tester.tap(find.text('Analisi'));
      await tester.pumpAndSettle();
      final states = shellStates(tester);

      await _resize(tester, const Size(900, 800));
      expect(router.location, '/finance/analytics');
      expect(tester.widget<NavigationRail>(_rail).selectedIndex, 2);
      expect(find.text('G1 · Analisi'), findsOneWidget);
      expectSameStates(states, shellStates(tester));

      await _resize(tester, const Size(400, 800));
      expect(router.location, '/finance/analytics');
      expect(tester.widget<NavigationBar>(_bottomBar).selectedIndex, 2);
      expectSameStates(states, shellStates(tester));

      // Back still goes to the first tab.
      await systemBack(tester);
      expect(router.location, '/finance/summary');
    });
  });

  group('centred column at 1280 dp', () {
    void expectCentred(WidgetTester tester, Rect area) {
      final column = tester.getRect(_column);
      expect(column.width, AppSizes.maxContentWidth);
      expect(column.center.dx, closeTo(area.center.dx, 0.5));
    }

    testWidgets('a placeholder screen', (tester) async {
      await pumpApp(tester, location: '/settings/appearance', window: _wide);
      expect(find.text('I3 · Aspetto'), findsOneWidget);
      expectCentred(tester, Offset.zero & _wide);
    });

    testWidgets('the account screen', (tester) async {
      await pumpApp(tester, location: '/settings/account', window: _wide);
      expect(find.text('I2 · Account'), findsOneWidget);
      expectCentred(tester, Offset.zero & _wide);
    });

    testWidgets('a tab next to the side bar', (tester) async {
      await pumpApp(tester, location: '/finance/analytics', window: _wide);
      final railRight = tester.getRect(_rail).right;
      expectCentred(
        tester,
        Rect.fromLTRB(railRight, 0, _wide.width, _wide.height),
      );
    });

    testWidgets('a detail above the section', (tester) async {
      await pumpApp(
        tester,
        location: '/finance/accounts/$exampleId',
        window: _wide,
      );
      expect(find.text('H2 · Dettaglio conto'), findsOneWidget);
      expectCentred(tester, Offset.zero & _wide);
    });

    testWidgets('sign-in', (tester) async {
      await pumpApp(
        tester,
        location: '/sign-in',
        auth: FakeAuthRepository(signedIn: false),
        window: _wide,
      );
      expect(find.byType(SignInScreen), findsOneWidget);
      expectCentred(tester, Offset.zero & _wide);
    });

    testWidgets('first access', (tester) async {
      await pumpApp(
        tester,
        location: '/welcome',
        accounts: FakeAccountRepository(status: newAccount),
        window: _wide,
      );
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expectCentred(tester, Offset.zero & _wide);
    });

    testWidgets('the hub, until its layouts', (tester) async {
      await pumpApp(tester, window: _wide);
      expect(find.byType(HubScreen), findsOneWidget);
      expectCentred(tester, Offset.zero & _wide);
    });

    testWidgets('a bottom sheet is at most 640 dp wide', (tester) async {
      await pumpApp(tester, location: '/finance/summary', window: _wide);
      await tester.tap(_railButton);
      await tester.pumpAndSettle();

      // The surface of the sheet; the widget around it spans the window.
      final sheet = tester.getRect(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(sheet.width, AppSizes.maxContentWidth);
      expect(sheet.center.dx, closeTo(_wide.width / 2, 0.5));
      expect(
        Theme.of(tester.element(_rail)).bottomSheetTheme.constraints?.maxWidth,
        AppSizes.maxContentWidth,
      );
    });
  });

  group('orientation', () {
    test('a phone display stays in portrait', () {
      // Short side 400 dp, at 3 pixels per dp.
      expect(preferredOrientations(const Size(1200, 2400), 3), const [
        DeviceOrientation.portraitUp,
      ]);
      expect(preferredOrientations(const Size(2400, 1200), 3), const [
        DeviceOrientation.portraitUp,
      ]);
      // Just under the limit.
      expect(preferredOrientations(const Size(1199, 2400), 2), const [
        DeviceOrientation.portraitUp,
      ]);
    });

    test('a tablet display turns freely', () {
      // Short side 800 dp, at 2 pixels per dp: no preference.
      expect(preferredOrientations(const Size(1600, 2560), 2), isEmpty);
      expect(preferredOrientations(const Size(2560, 1600), 2), isEmpty);
      // Exactly at the limit.
      expect(preferredOrientations(const Size(1200, 1920), 2), isEmpty);
    });
  });

  group('large text', () {
    testWidgets('the side bar at 600 × 480 with the text at 200% fits', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = AppTextScale.max;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(
        tester,
        location: '/finance/summary',
        window: const Size(600, 480),
      );

      expect(tester.takeException(), isNull);
      expect(_rail, findsOneWidget);
      expect(_railButton, findsOneWidget);
      // The labels have the limit of the bottom bar.
      final label = find.descendant(of: _rail, matching: find.text('Conti'));
      expect(
        MediaQuery.textScalerOf(tester.element(label)).scale(10),
        closeTo(10 * AppTextScale.barLabelMax, 1e-9),
      );
      // When the tabs do not fit, they scroll.
      expect(
        find.descendant(of: _rail, matching: find.byType(Scrollable)),
        findsOneWidget,
      );
      final conti = find.descendant(of: _rail, matching: find.text('Conti'));
      await tester.ensureVisible(conti);
      await tester.pumpAndSettle();
      await tester.tap(conti);
      await tester.pumpAndSettle();
      expect(find.text('H1 · I tuoi conti'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the side bar is the same component', (tester) async {
      await pumpApp(tester, location: '/finance/summary', window: _medium);
      expect(find.byType(SectionRail), findsOneWidget);
    });
  });
}
