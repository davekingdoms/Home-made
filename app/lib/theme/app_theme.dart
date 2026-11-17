import 'package:homemade/theme/app_button_styles.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/casa_colors.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/page_transitions.dart';
import 'package:homemade/theme/text_scale.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Theme of [palette] for [brightness]: one of the six combinations of
/// `docs/spec/stile.md` (section 10).
ThemeData buildAppTheme(AppPalette palette, Brightness brightness) {
  final tokens = tokensOf(palette, brightness);
  final scheme = _colorScheme(tokens, brightness);
  final colors = AppColors.fromTokens(tokens, brightness);
  final textTheme = appTextTheme;

  final disabledContent = scheme.onSurface.withValues(
    alpha: AppOpacities.disabledContent,
  );
  final disabledContainer = scheme.onSurface.withValues(
    alpha: AppOpacities.disabledContainer,
  );
  final focusRing = BorderSide(
    color: scheme.secondary,
    width: AppSizes.focusRing,
    strokeAlign: BorderSide.strokeAlignOutside,
  );
  // Buttons are pills; the focus ring adds to the state layer (section 8).
  final buttonBase = ButtonStyle(
    shape: const WidgetStatePropertyAll(StadiumBorder()),
    textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
    iconSize: const WidgetStatePropertyAll(AppSizes.iconSmall),
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused) ? focusRing : null,
    ),
  );
  const mainButtonSize = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(
      Size(AppSizes.minTouchTarget, AppSizes.buttonHeight),
    ),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: AppSpacing.xl),
    ),
  );

  OutlineInputBorder fieldBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.textField),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: appFontFamily,
    textTheme: textTheme,
    extensions: [
      colors,
      CasaColors.of(palette),
      AppButtonStyles.fromScheme(scheme),
    ],
    // One icon set: Material Symbols Rounded, outlined (section 5).
    iconTheme: IconThemeData(
      color: scheme.onSurface,
      size: AppSizes.icon,
      fill: 0,
      weight: 400,
      grade: 0,
      opticalSize: AppSizes.icon,
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) =>
          const Icon(Symbols.arrow_back_rounded),
      closeButtonIconBuilder: (context) => const Icon(Symbols.close_rounded),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: AppSizes.topBarHeight,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      // Filled on the active tab only.
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
          size: AppSizes.icon,
          fill: selected ? 1 : 0,
          weight: 400,
          grade: 0,
          opticalSize: AppSizes.icon,
        );
      }),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: colors.badge,
      textColor: colors.onBadge,
      textStyle: textTheme.labelSmall,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: buttonBase.merge(mainButtonSize),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: mainButtonSize.copyWith(
        shape: buttonBase.shape,
        textStyle: buttonBase.textStyle,
        iconSize: buttonBase.iconSize,
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: disabledContainer);
          }
          if (states.contains(WidgetState.focused)) return focusRing;
          return BorderSide(color: scheme.outline);
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: buttonBase.copyWith(
        minimumSize: const WidgetStatePropertyAll(
          Size(AppSizes.minTouchTarget, AppSizes.compactButtonHeight),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      iconSize: AppSizes.icon,
      sizeConstraints: const BoxConstraints.tightFor(
        width: AppSizes.fab,
        height: AppSizes.fab,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.fab),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        selectedForegroundColor: scheme.onSecondaryContainer,
        selectedBackgroundColor: scheme.secondaryContainer,
        textStyle: textTheme.labelLarge,
        side: BorderSide(color: scheme.outline),
        shape: const StadiumBorder(),
      ),
      selectedIcon: const Icon(Symbols.check_rounded),
    ),
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return selected ? disabledContainer : Colors.transparent;
        }
        return selected ? scheme.secondaryContainer : Colors.transparent;
      }),
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return BorderSide.none;
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: disabledContainer);
        }
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: scheme.onSurfaceVariant);
        }
        return BorderSide(color: scheme.outline);
      }),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      labelStyle: textTheme.labelLarge?.copyWith(
        color: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledContent;
          return states.contains(WidgetState.selected)
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant;
        }),
      ),
      checkmarkColor: scheme.onSecondaryContainer,
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return selected ? scheme.surface : disabledContent;
        }
        return selected ? scheme.onPrimary : scheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return selected
              ? disabledContainer
              : scheme.surfaceContainerHighest.withValues(
                  alpha: AppOpacities.disabledContainer,
                );
        }
        return selected ? scheme.primary : scheme.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return states.contains(WidgetState.disabled)
            ? disabledContainer
            : scheme.outline;
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabledContent;
        return states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.onSurfaceVariant;
      }),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      contentPadding: const EdgeInsets.all(AppSpacing.md),
      border: fieldBorder(scheme.outline),
      enabledBorder: fieldBorder(scheme.outline),
      focusedBorder: fieldBorder(scheme.primary, width: 2),
      errorBorder: fieldBorder(scheme.error),
      focusedErrorBorder: fieldBorder(scheme.error, width: 2),
      disabledBorder: fieldBorder(disabledContainer),
      // Material keeps helper and error texts on one line and cuts them:
      // with the text at 200% (section 7) they need room to wrap.
      helperMaxLines: AppTextScale.maxFieldMessageLines,
      errorMaxLines: AppTextScale.maxFieldMessageLines,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: scheme.onSurfaceVariant,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
    ),
    listTileTheme: ListTileThemeData(
      minTileHeight: AppSizes.listRowMinHeight,
      // A two-line ListTile whose lines do not fit the Material offsets falls
      // back to a compact layout, as tall as its lines plus this padding
      // twice, which ignores the minimum height: with this padding a title
      // and a subtitle fill the minimum row exactly.
      minVerticalPadding:
          (AppSizes.listRowMinHeight -
              _lineHeight(textTheme.bodyLarge) -
              _lineHeight(textTheme.bodySmall)) /
          2,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenMargin,
      ),
      iconColor: scheme.onSurfaceVariant,
      // With a colour: a ListTile paints an enabled title in the colour of
      // this style, and the type scale has none.
      titleTextStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    // Pull to refresh.
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      refreshBackgroundColor: scheme.surfaceContainerHigh,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: AppPageTransitionsBuilder()},
    ),
  );
}

/// Height of one line of [style], in dp.
double _lineHeight(TextStyle? style) => style!.fontSize! * style.height!;

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
