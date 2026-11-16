import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/features/dev/screen_index_screen.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/pump_app.dart';

/// Narrows [finder] to the open bottom sheet: the screen under it stays
/// visible.
Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

void main() {
  final screens = screenCatalog.where((entry) => !entry.isSheet).toList();
  final sheets = screenCatalog.where((entry) => entry.isSheet).toList();

  group('catalog', () {
    test('has the 31 screens and 7 sheets of the specification', () {
      expect(screens, hasLength(31));
      expect(sheets, hasLength(7));
    });

    test('has unique codes and paths', () {
      final codes = screenCatalog.map((entry) => entry.code).toSet();
      final paths = screens.map((entry) => entry.path).toSet();
      expect(codes, hasLength(screenCatalog.length));
      expect(paths, hasLength(screens.length));
    });

    test('links only to codes that exist', () {
      for (final entry in screenCatalog) {
        for (final code in entry.opens) {
          expect(() => screenByCode(code), returnsNormally, reason: code);
        }
      }
    });
  });

  group('every screen opens at its path', () {
    for (final entry in screens) {
      for (final location in entry.exampleLocations.keys) {
        testWidgets('${entry.code} at $location', (tester) async {
          final router = await pumpApp(
            tester,
            location: location,
            // With a session, sign-in (A2) leads to the hub.
            auth: FakeAuthRepository(signedIn: entry.code != 'A2'),
          );

          expect(router.location, location);
          if (entry.code == 'B1') {
            expect(find.byType(HubScreen), findsOneWidget);
            expect(find.text('Home-made'), findsOneWidget);
            return;
          }
          expect(find.text(entry.label), findsOneWidget);
          expect(find.text('Segnaposto'), findsOneWidget);
          // The bottom bar shows on the tabs only.
          expect(
            find.byType(NavigationBar),
            entry.level == ScreenLevel.section ? findsOneWidget : findsNothing,
          );
        });
      }
    }
  });

  group('every sheet opens from the screen index', () {
    for (final entry in sheets) {
      testWidgets(entry.code, (tester) async {
        await pumpApp(tester, location: screenIndexPath);
        final tile = find.byKey(ValueKey('index-${entry.code}'));
        await tester.scrollUntilVisible(tile, 200);
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsOneWidget);
        expect(inSheet(find.text(entry.label)), findsOneWidget);
        expect(inSheet(find.text('Segnaposto')), findsOneWidget);

        await systemBack(tester);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(ScreenIndexScreen), findsOneWidget);
      });
    }
  });

  group('hub', () {
    testWidgets('opens Finance, settings and the screen index', (tester) async {
      final router = await pumpApp(tester);

      await tester.tap(find.text('Finanze'));
      await tester.pumpAndSettle();
      expect(router.location, '/finance/summary');

      await tester.tap(find.text('Finanze'));
      await tester.pumpAndSettle();
      expect(router.location, '/');

      await tester.tap(find.byTooltip('Impostazioni'));
      await tester.pumpAndSettle();
      expect(router.location, '/settings');

      await systemBack(tester);
      await tester.tap(find.text('Indice delle schermate'));
      await tester.pumpAndSettle();
      expect(find.byType(ScreenIndexScreen), findsOneWidget);
    });

    testWidgets('sections that are not built yet cannot be tapped', (
      tester,
    ) async {
      final router = await pumpApp(tester);

      expect(find.text('In arrivo'), findsNWidgets(3));
      for (final name in ['Dispensa', 'Documenti', 'Animali']) {
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
        expect(router.location, '/');
      }
    });
  });

  group('system back', () {
    testWidgets('goes from Movimenti to Riepilogo, then to the hub', (
      tester,
    ) async {
      final router = await pumpApp(tester);
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

    testWidgets('closes the sheet, then the detail, then leaves the tab', (
      tester,
    ) async {
      final router = await pumpApp(
        tester,
        location: '/finance/transactions/$exampleId',
      );
      await tester.tap(find.byKey(const ValueKey('open-E2')));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('E2 · Scelta categoria')), findsOneWidget);

      await systemBack(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('E1 · Dettaglio transazione'), findsOneWidget);

      await systemBack(tester);
      expect(find.text('D1 · Movimenti'), findsOneWidget);

      await systemBack(tester);
      expect(find.text('C1 · Riepilogo'), findsOneWidget);

      await systemBack(tester);
      expect(router.location, '/');
    });

    testWidgets('goes from settings to the hub', (tester) async {
      final router = await pumpApp(tester, location: '/settings/account');

      await systemBack(tester);
      expect(router.location, '/settings');

      await systemBack(tester);
      expect(router.location, '/');
    });
  });

  group('"+" button', () {
    testWidgets('shows on Riepilogo and Movimenti only', (tester) async {
      await pumpApp(tester, location: '/finance/summary');
      expect(find.byType(FloatingActionButton), findsOneWidget);

      await tester.tap(find.text('Movimenti'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);

      for (final tab in ['Analisi', 'Conti']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(find.byType(FloatingActionButton), findsNothing);
      }
    });

    testWidgets('opens F1, from which F2 opens above the section', (
      tester,
    ) async {
      final router = await pumpApp(tester, location: '/finance/transactions');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('F1 · Menu "+"')), findsOneWidget);
      expect(
        inSheet(find.text('F2 · Nuovo movimento · Giroconto o prelievo')),
        findsOneWidget,
      );

      await tester.tap(find.text('F2 · Nuovo movimento · Entrata'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('F2 · Nuovo movimento'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await systemBack(tester);
      expect(find.text('D1 · Movimenti'), findsOneWidget);
      expect(router.location, '/finance/transactions');
    });
  });

  testWidgets('each tab keeps its place in the bar order', (tester) async {
    final router = await pumpApp(tester, location: '/finance/summary');
    const tabs = {
      'Movimenti': '/finance/transactions',
      'Analisi': '/finance/analytics',
      'Conti': '/finance/accounts',
      'Riepilogo': '/finance/summary',
    };
    for (final tab in tabs.entries) {
      await tester.tap(find.text(tab.key));
      await tester.pumpAndSettle();
      expect(router.location, tab.value);
    }
  });
}
