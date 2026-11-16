import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Radii from section 4 of `docs/spec/stile.md`.
abstract final class AppRadii {
  static const double fab = 16;
  static const double card = 28;
  static const double hubCard = 32;
  static const double sheet = 28;
}

/// Theme of [palette] for [brightness].
ThemeData buildAppTheme(AppPalette palette, Brightness brightness) {
  final variants = paletteTokens[palette]!;
  final tokens = brightness == Brightness.dark ? variants.dark : variants.light;
  final scheme = _colorScheme(tokens, brightness);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: appTextTheme,
    extensions: [AppColors.fromTokens(tokens)],
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll(appTextTheme.labelMedium),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.fab),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
  );
}

ColorScheme _colorScheme(PaletteTokens t, Brightness brightness) => ColorScheme(
  brightness: brightness,
  primary: t.primary,
  onPrimary: t.onPrimary,
  primaryContainer: t.primaryContainer,
  onPrimaryContainer: t.onPrimaryContainer,
  secondary: t.secondary,
  onSecondary: t.onSecondary,
  secondaryContainer: t.secondaryContainer,
  onSecondaryContainer: t.onSecondaryContainer,
  tertiary: t.tertiary,
  onTertiary: t.onTertiary,
  tertiaryContainer: t.tertiaryContainer,
  onTertiaryContainer: t.onTertiaryContainer,
  error: t.error,
  onError: t.onError,
  errorContainer: t.errorContainer,
  onErrorContainer: t.onErrorContainer,
  surface: t.surface,
  onSurface: t.onSurface,
  onSurfaceVariant: t.onSurfaceVariant,
  surfaceContainerLowest: t.surfaceContainerLowest,
  surfaceContainerLow: t.surfaceContainerLow,
  surfaceContainer: t.surfaceContainer,
  surfaceContainerHigh: t.surfaceContainerHigh,
  surfaceContainerHighest: t.surfaceContainerHighest,
  surfaceDim: t.surfaceDim,
  surfaceBright: t.surfaceBright,
  outline: t.outline,
  outlineVariant: t.outlineVariant,
  inverseSurface: t.inverseSurface,
  onInverseSurface: t.onInverseSurface,
  inversePrimary: t.inversePrimary,
  shadow: t.shadow,
  scrim: t.scrim,
  surfaceTint: t.surfaceTint,
);
