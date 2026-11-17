import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/theme/app_button_styles.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/app_theme.dart';
import 'package:homemade/theme/appearance.dart';
import 'package:homemade/theme/casa_colors.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/page_transitions.dart';
import 'package:homemade/theme/text_scale.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/pump_app.dart';
import 'helpers/spec.dart';

void main() {
  group('tokens', () {
    final table = readPaletteTable();

    test('the specification table has the six columns in order', () {
      expect(table.headers, combinationHeaders);
    });

    test('there is a palette for each of the three of the specification', () {
      expect(AppPalette.values.map((palette) => palette.label), [
        'Teal',
        'Dollari',
        'Soldi mauriziani',
      ]);
      expect(paletteTokens.keys, AppPalette.values);
    });

    for (final (index, combination) in combinations.indexed) {
      final (palette, brightness) = combination;

      test('${combinationHeaders[index]} matches section 2.1 of stile.md', () {
        final column = table.columns[index];
        expect(column, hasLength(40));
        expect(tokensOf(palette, brightness).byRole, column);
      });
    }

    test('the fixed colours do not depend on the palette', () {
      for (final (palette, brightness) in combinations) {
        final tokens = tokensOf(palette, brightness);
        final colors = AppColors.fromTokens(tokens, brightness);
        final dark = brightness == Brightness.dark;

        expect(colors.nastroGiallo, nastroGiallo);
        expect(colors.nastroNero, nastroNero);
        // Counter badge: fixed in the dark theme, error roles in the light.
        expect(colors.badge, dark ? counterBadgeDark : tokens.error);
        expect(colors.onBadge, dark ? onCounterBadgeDark : tokens.onError);
      }
    });
  });

  group('theme', () {
    for (final combination in combinations) {
      final (palette, brightness) = combination;
      final name = describeCombination(combination);
      final tokens = tokensOf(palette, brightness);

      test('$name takes every colour from the tokens', () {
        final theme = buildAppTheme(palette, brightness);
        final scheme = theme.colorScheme;
        final colors = theme.extension<AppColors>()!;

        expect(scheme.brightness, brightness);
        expect({
          'primary': scheme.primary,
          'onPrimary': scheme.onPrimary,
          'primaryContainer': scheme.primaryContainer,
          'onPrimaryContainer': scheme.onPrimaryContainer,
          'secondary': scheme.secondary,
          'onSecondary': scheme.onSecondary,
          'secondaryContainer': scheme.secondaryContainer,
          'onSecondaryContainer': scheme.onSecondaryContainer,
          'tertiary': scheme.tertiary,
          'onTertiary': scheme.onTertiary,
          'tertiaryContainer': scheme.tertiaryContainer,
          'onTertiaryContainer': scheme.onTertiaryContainer,
          'error': scheme.error,
          'onError': scheme.onError,
          'errorContainer': scheme.errorContainer,
          'onErrorContainer': scheme.onErrorContainer,
          'surface': scheme.surface,
          'onSurface': scheme.onSurface,
          'onSurfaceVariant': scheme.onSurfaceVariant,
          'surfaceContainerLowest': scheme.surfaceContainerLowest,
          'surfaceContainerLow': scheme.surfaceContainerLow,
          'surfaceContainer': scheme.surfaceContainer,
          'surfaceContainerHigh': scheme.surfaceContainerHigh,
          'surfaceContainerHighest': scheme.surfaceContainerHighest,
          'surfaceDim': scheme.surfaceDim,
          'surfaceBright': scheme.surfaceBright,
          'outline': scheme.outline,
          'outlineVariant': scheme.outlineVariant,
          'inverseSurface': scheme.inverseSurface,
          'onInverseSurface': scheme.onInverseSurface,
          'inversePrimary': scheme.inversePrimary,
          'shadow': scheme.shadow,
          'scrim': scheme.scrim,
          'surfaceTint': scheme.surfaceTint,
          'testoTerziario': colors.testoTerziario,
          'banda': colors.banda,
          'suPrimarioTenue': colors.suPrimarioTenue,
          'avviso': colors.avviso,
          'credito': colors.credito,
          'debito': colors.debito,
        }, tokens.byRole);
        expect(scheme.surfaceTint.a, 0);
      });

      test('$name has the house colours of its palette, at night', () {
        final theme = buildAppTheme(palette, brightness);
        final casa = theme.extension<CasaColors>()!;
        final night = CasaColors.of(palette);

        for (final role in CasaRole.values) {
          expect(casa[role], night[role], reason: role.name);
        }
      });

      test('$name themes the components of section 8', () {
        final theme = buildAppTheme(palette, brightness);
        final styles = theme.extension<AppButtonStyles>()!;
        const noState = <WidgetState>{};

        expect(theme.textTheme.bodyMedium?.fontFamily, appFontFamily);
        expect(theme.appBarTheme.toolbarHeight, AppSizes.topBarHeight);
        expect(
          theme.navigationBarTheme.labelBehavior,
          NavigationDestinationLabelBehavior.alwaysShow,
        );
        expect(
          theme.navigationBarTheme.indicatorColor,
          tokens.secondaryContainer,
        );
        expect(theme.navigationBarTheme.indicatorShape, const StadiumBorder());
        // Filled icon on the active tab only.
        final navigationIcons = theme.navigationBarTheme.iconTheme!;
        expect(navigationIcons.resolve({WidgetState.selected})?.fill, 1);
        expect(navigationIcons.resolve(noState)?.fill, 0);

        final filled = theme.filledButtonTheme.style!;
        expect(filled.shape?.resolve(noState), const StadiumBorder());
        expect(
          filled.minimumSize?.resolve(noState)?.height,
          AppSizes.buttonHeight,
        );
        expect(
          styles.compact.minimumSize?.resolve(noState)?.height,
          AppSizes.compactButtonHeight,
        );
        expect(
          styles.tonal.backgroundColor?.resolve(noState),
          tokens.surfaceContainerHighest,
        );
        expect(styles.tonal.foregroundColor?.resolve(noState), tokens.primary);
        expect(
          styles.destructive.foregroundColor?.resolve(noState),
          tokens.error,
        );
        final outlined = theme.outlinedButtonTheme.style!;
        expect(outlined.side?.resolve(noState)?.color, tokens.outline);
        // Focus adds a ring.
        expect(
          filled.side?.resolve({WidgetState.focused})?.width,
          AppSizes.focusRing,
        );

        expect(
          theme.floatingActionButtonTheme.shape,
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.fab),
          ),
        );
        expect(
          theme.floatingActionButtonTheme.sizeConstraints,
          const BoxConstraints.tightFor(
            width: AppSizes.fab,
            height: AppSizes.fab,
          ),
        );
        expect(
          theme.chipTheme.shape,
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
        );
        expect(
          theme.switchTheme.trackColor?.resolve({WidgetState.selected}),
          tokens.primary,
        );
        expect(
          theme.radioTheme.fillColor?.resolve({WidgetState.selected}),
          tokens.primary,
        );
        expect(
          theme.inputDecorationTheme.border,
          isA<OutlineInputBorder>().having(
            (border) => border.borderRadius,
            'borderRadius',
            BorderRadius.circular(AppRadii.textField),
          ),
        );
        expect(
          theme.bottomSheetTheme.shape,
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadii.sheet),
            ),
          ),
        );
        expect(theme.cardTheme.color, tokens.surfaceContainerLow);
        expect(
          theme.cardTheme.shape,
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
        );
        expect(theme.listTileTheme.minTileHeight, AppSizes.listRowMinHeight);
        expect(theme.progressIndicatorTheme.color, tokens.primary);
      });

      test('$name keeps the predictive back with the shared axis', () {
        final theme = buildAppTheme(palette, brightness);
        final builder =
            theme.pageTransitionsTheme.builders[TargetPlatform.android];

        expect(builder, isA<AppPageTransitionsBuilder>());
        expect(builder, isA<PredictiveBackPageTransitionsBuilder>());
      });
    }

    test('the radii and sizes are those of section 4', () {
      expect(AppRadii.small, 8);
      expect(AppRadii.textField, 12);
      expect(AppRadii.fab, 16);
      expect(AppRadii.inner, 20);
      expect(AppRadii.choiceRow, 24);
      expect(AppRadii.card, 28);
      expect(AppRadii.sheet, 28);
      expect(AppRadii.hubCard, 32);
      expect(AppSizes.minTouchTarget, 48);
      expect(AppSizes.compactButtonHeight, 44);
      expect(AppSizes.buttonHeight, inInclusiveRange(52, 56));
      expect(AppSizes.fab, 56);
      expect(AppSizes.listRowMinHeight, inInclusiveRange(60, 64));
      expect(AppSizes.topBarHeight, 64);
    });
  });

  group('app', () {
    for (final brightness in Brightness.values) {
      testWidgets('starts in Teal and follows the system: ${brightness.name}', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await pumpApp(tester);

        final tokens = tokensOf(AppPalette.teal, brightness);
        final theme = Theme.of(tester.element(find.byType(HubScreen)));
        expect(theme.brightness, brightness);
        expect(theme.colorScheme.primary, tokens.primary);
        expect(theme.colorScheme.surface, tokens.surface);
      });
    }

    testWidgets('the chosen palette and theme apply to the whole app', (
      tester,
    ) async {
      await pumpApp(tester);
      final element = tester.element(find.byType(HubScreen));
      final container = ProviderScope.containerOf(element);
      expect(container.read(appearanceControllerProvider), const Appearance());

      container.read(appearanceControllerProvider.notifier)
        ..choosePalette(AppPalette.mauriziani)
        ..chooseThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();

      final theme = Theme.of(tester.element(find.byType(HubScreen)));
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, maurizianiDark.primary);
      expect(theme.extension<AppColors>()!.banda, maurizianiDark.banda);
    });

    testWidgets('is in Italian, Material texts included', (tester) async {
      await pumpApp(tester);
      final context = tester.element(find.byType(HubScreen));

      expect(Localizations.localeOf(context), const Locale('it'));
      expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Annulla');
    });

    testWidgets('limits the system text size to 200%', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester);
      final context = tester.element(find.byType(HubScreen));

      expect(MediaQuery.textScalerOf(context).scale(10), 20);
      // The hub will limit itself further, to 130%.
      expect(AppTextScale.hubScalerOf(context).scale(10), 13);
    });
  });

  group('type scale', () {
    test('matches section 3 of stile.md', () {
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
        expect(style.fontFamily, appFontFamily);
        expect(style.fontSize, size);
        expect(style.fontSize! * style.height!, closeTo(line, 1e-9));
        // The weight is set twice: as a weight and on the variable axis.
        expect(style.fontWeight, weight);
        expect(style.fontVariations, [
          FontVariation('wght', weight.value.toDouble()),
        ]);
      }
    });

    test('amounts have tabular figures, and weight 600 in lists', () {
      final amount = appTextTheme.titleMedium!.amount;
      expect(amount.fontFeatures, const [FontFeature.tabularFigures()]);
      expect(amount.fontWeight, FontWeight.w500);

      final listAmount = appTextTheme.bodyLarge!.listAmount;
      expect(listAmount.fontFeatures, const [FontFeature.tabularFigures()]);
      expect(listAmount.fontWeight, FontWeight.w600);
      expect(listAmount.fontVariations, const [FontVariation('wght', 600)]);
    });
  });
}
