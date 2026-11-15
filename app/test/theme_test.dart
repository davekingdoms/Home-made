import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/app_theme.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/pump_app.dart';

/// Columns of the table in section 2.1 of the style specification.
enum _Column { tealDark, tealLight }

/// Reads the role table of section 2.1: role name to colour, per column.
Map<_Column, Map<String, Color>> _readSpecTable() {
  // Tests run from app/: the specification is in the repository root.
  final lines = File('../docs/spec/stile.md').readAsLinesSync();
  final start = lines.indexWhere((line) => line.startsWith('### 2.1'));
  final row = RegExp(r'^\| `(\w+)` \| (\S+) \| (\S+) \|');
  final table = {
    for (final column in _Column.values) column: <String, Color>{},
  };
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('#')) break;
    final match = row.firstMatch(line);
    if (match == null) continue;
    table[_Column.tealDark]![match[1]!] = _parseColor(match[2]!);
    table[_Column.tealLight]![match[1]!] = _parseColor(match[3]!);
  }
  return table;
}

Color _parseColor(String value) {
  if (value == 'trasparente') return const Color(0x00000000);
  if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(value)) {
    throw FormatException('Not a colour of the specification table', value);
  }
  return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
}

void main() {
  group('tokens', () {
    final table = _readSpecTable();

    test('the specification table has all the roles', () {
      expect(table[_Column.tealDark], hasLength(40));
      expect(table[_Column.tealLight], hasLength(40));
    });

    test('Teal scuro matches section 2.1 of stile.md', () {
      expect(tealDark.byRole, table[_Column.tealDark]);
    });

    test('Teal chiaro matches section 2.1 of stile.md', () {
      expect(tealLight.byRole, table[_Column.tealLight]);
    });
  });

  group('theme', () {
    for (final brightness in Brightness.values) {
      final tokens = brightness == Brightness.dark ? tealDark : tealLight;

      test('${brightness.name} takes every colour from the tokens', () {
        final theme = buildAppTheme(AppPalette.teal, brightness);
        final scheme = theme.colorScheme;
        final colors = theme.extension<AppColors>()!;

        expect(scheme.brightness, brightness);
        expect(scheme.primary, tokens.primary);
        expect(scheme.secondaryContainer, tokens.secondaryContainer);
        expect(scheme.surface, tokens.surface);
        expect(scheme.surfaceContainerLow, tokens.surfaceContainerLow);
        expect(scheme.outlineVariant, tokens.outlineVariant);
        expect(scheme.surfaceTint, const Color(0x00000000));
        expect(colors.testoTerziario, tokens.testoTerziario);
        expect(colors.banda, tokens.banda);
        expect(colors.suPrimarioTenue, tokens.suPrimarioTenue);
        expect(colors.avviso, tokens.avviso);
        expect(colors.credito, tokens.credito);
        expect(colors.debito, tokens.debito);
        expect(colors.nastroGiallo, nastroGiallo);
        expect(colors.nastroNero, nastroNero);
      });

      test('${brightness.name} themes the placeholder components', () {
        final theme = buildAppTheme(AppPalette.teal, brightness);

        expect(
          theme.navigationBarTheme.labelBehavior,
          NavigationDestinationLabelBehavior.alwaysShow,
        );
        expect(
          theme.navigationBarTheme.indicatorColor,
          tokens.secondaryContainer,
        );
        expect(theme.cardTheme.color, tokens.surfaceContainerLow);
        expect(
          theme.cardTheme.shape,
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        );
        expect(
          theme.floatingActionButtonTheme.shape,
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        );
        expect(
          theme.bottomSheetTheme.shape,
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
        );
        expect(
          theme.pageTransitionsTheme.builders[TargetPlatform.android],
          isA<PredictiveBackPageTransitionsBuilder>(),
        );
      });

      testWidgets('the app builds in the ${brightness.name} theme', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await pumpApp(tester);

        final theme = Theme.of(tester.element(find.byType(HubScreen)));
        expect(theme.brightness, brightness);
        expect(theme.colorScheme.primary, tokens.primary);
        expect(theme.colorScheme.surface, tokens.surface);
      });
    }
  });

  test('the type scale matches section 3 of stile.md', () {
    // Size, line height and weight of each role.
    final scale = {
      appTextTheme.displaySmall: (40, 48, FontWeight.w500),
      appTextTheme.headlineLarge: (32, 40, FontWeight.w500),
      appTextTheme.headlineMedium: (28, 36, FontWeight.w500),
      appTextTheme.headlineSmall: (24, 32, FontWeight.w500),
      appTextTheme.titleLarge: (22, 28, FontWeight.w500),
      appTextTheme.titleMedium: (17, 24, FontWeight.w500),
      appTextTheme.titleSmall: (15, 20, FontWeight.w500),
      appTextTheme.bodyLarge: (16, 24, FontWeight.w400),
      appTextTheme.bodyMedium: (15, 22, FontWeight.w400),
      appTextTheme.bodySmall: (13, 18, FontWeight.w400),
      appTextTheme.labelLarge: (14, 20, FontWeight.w600),
      appTextTheme.labelMedium: (12, 16, FontWeight.w500),
      appTextTheme.labelSmall: (11, 16, FontWeight.w600),
    };
    for (final MapEntry(key: style!, value: (size, line, weight))
        in scale.entries) {
      expect(style.fontSize, size);
      expect(style.fontSize! * style.height!, closeTo(line, 1e-9));
      expect(style.fontWeight, weight);
    }
  });
}
