import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/features/dev/component_catalog.dart';
import 'package:homemade/features/dev/component_catalog_screen.dart';
import 'package:homemade/features/dev/screen_index_screen.dart';
import 'package:homemade/theme/appearance.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/design_harness.dart';
import 'helpers/pump_app.dart';
import 'helpers/spec.dart';

const _path = '/dev/components';

/// The list of the catalog: the first scrollable, around the others.
Finder get _list => find.byType(Scrollable).first;

Finder _component(CatalogEntry entry) =>
    find.byKey(ValueKey('component-${entry.id}'));

ThemeData _themeOf(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(ComponentCatalogScreen)));

/// Scrolls through the whole catalog, building every component.
Future<void> _scrollThrough(WidgetTester tester) async {
  for (final entry in componentCatalog) {
    await tester.scrollUntilVisible(_component(entry), 300, scrollable: _list);
    expect(tester.takeException(), isNull, reason: entry.id);
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('opens from the screen index, and back returns there', (
    tester,
  ) async {
    await pumpApp(tester, location: screenIndexPath);
    final tile = find.byKey(const ValueKey('index-$componentCatalogCode'));
    await tester.scrollUntilVisible(tile, 200);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.byType(ComponentCatalogScreen), findsOneWidget);
    expect(find.text('Catalogo dei componenti'), findsOneWidget);

    await systemBack(tester);
    expect(find.byType(ComponentCatalogScreen), findsNothing);
    expect(find.byType(ScreenIndexScreen), findsOneWidget);
  });

  testWidgets('opens at its path and shows every component', (tester) async {
    final router = await pumpApp(tester, location: _path);

    expect(router.location, _path);
    expect(find.byType(ComponentCatalogScreen), findsOneWidget);
    for (final entry in componentCatalog) {
      await tester.scrollUntilVisible(
        _component(entry),
        300,
        scrollable: _list,
      );
      expect(find.text(entry.title), findsWidgets);
    }
  });

  for (final combination in combinations) {
    final (palette, brightness) = combination;

    testWidgets('builds in ${describeCombination(combination)}', (
      tester,
    ) async {
      await pumpApp(tester, location: _path);
      ProviderScope.containerOf(
          tester.element(find.byType(ComponentCatalogScreen)),
        ).read(appearanceControllerProvider.notifier)
        ..choosePalette(palette)
        ..chooseThemeMode(
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        );
      await tester.pumpAndSettle();

      final theme = _themeOf(tester);
      expect(theme.brightness, brightness);
      expect(theme.colorScheme.primary, tokensOf(palette, brightness).primary);
      await _scrollThrough(tester);
    });
  }

  testWidgets('the palette changes the theme of the whole app', (tester) async {
    await pumpApp(tester, location: _path);
    expect(_themeOf(tester).colorScheme.primary, tealLight.primary);

    await tester.tap(find.byKey(const ValueKey('palette-dollari')));
    await tester.pumpAndSettle();
    expect(_themeOf(tester).colorScheme.primary, dollariLight.primary);

    await tester.tap(find.byKey(const ValueKey('palette-mauriziani')));
    await tester.pumpAndSettle();
    expect(_themeOf(tester).colorScheme.primary, maurizianiLight.primary);

    // The choice is of the app, not of this screen.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ComponentCatalogScreen)),
    );
    expect(
      container.read(appearanceControllerProvider).palette,
      AppPalette.mauriziani,
    );
  });

  testWidgets('the theme can be Automatico, Chiaro or Scuro', (tester) async {
    await pumpApp(tester, location: _path);
    expect(_themeOf(tester).brightness, Brightness.light);

    await tester.tap(find.text('Scuro'));
    await tester.pumpAndSettle();
    expect(_themeOf(tester).brightness, Brightness.dark);
    expect(_themeOf(tester).colorScheme.primary, tealDark.primary);

    await tester.tap(find.text('Chiaro'));
    await tester.pumpAndSettle();
    expect(_themeOf(tester).brightness, Brightness.light);

    // Automatico follows the system.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.tap(find.text('Automatico'));
    await tester.pumpAndSettle();
    expect(_themeOf(tester).brightness, Brightness.dark);
  });

  testWidgets('the text of the components goes to 130% and 200%', (
    tester,
  ) async {
    await pumpApp(tester, location: _path);
    final first = _component(componentCatalog.first);
    double scaleOfComponents() => MediaQuery.textScalerOf(
      tester.element(
        find.descendant(of: first, matching: find.byType(Builder)).first,
      ),
    ).scale(10);

    expect(scaleOfComponents(), 10);

    for (final (label, scaled) in const [('130%', 13.0), ('200%', 20.0)]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(scaleOfComponents(), closeTo(scaled, 1e-9));
    }

    // The rest of the app keeps the size of the system.
    final screen = tester.element(find.byType(ComponentCatalogScreen));
    expect(MediaQuery.textScalerOf(screen).scale(10), 10);

    // Every component still fits at 200%.
    await _scrollThrough(tester);
  });
}
