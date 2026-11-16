import 'package:material_ui/material_ui.dart';

/// Family name of Google Sans Flex, as declared in `pubspec.yaml`.
const appFontFamily = 'GoogleSansFlex';

/// [style] in [weight]. Google Sans Flex is a variable font: the weight goes
/// both in `fontWeight` and on the `wght` axis (section 3 of
/// `docs/spec/stile.md`).
TextStyle withWeight(TextStyle style, FontWeight weight) => style.copyWith(
  fontWeight: weight,
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
);

TextStyle _style(double size, double lineHeight, FontWeight weight) =>
    withWeight(
      TextStyle(
        fontFamily: appFontFamily,
        fontSize: size,
        height: lineHeight / size,
        letterSpacing: 0,
      ),
      weight,
    );

/// Type scale from section 3 of `docs/spec/stile.md` (size/line height in dp,
/// weight), in Google Sans Flex.
final TextTheme appTextTheme = TextTheme(
  displaySmall: _style(40, 48, FontWeight.w500),
  headlineLarge: _style(32, 40, FontWeight.w500),
  headlineMedium: _style(28, 36, FontWeight.w500),
  headlineSmall: _style(24, 32, FontWeight.w500),
  titleLarge: _style(22, 28, FontWeight.w500),
  titleMedium: _style(17, 24, FontWeight.w500),
  titleSmall: _style(15, 20, FontWeight.w500),
  bodyLarge: _style(16, 24, FontWeight.w400),
  bodyMedium: _style(15, 22, FontWeight.w400),
  bodySmall: _style(13, 18, FontWeight.w400),
  labelLarge: _style(14, 20, FontWeight.w600),
  labelMedium: _style(12, 16, FontWeight.w500),
  labelSmall: _style(11, 16, FontWeight.w600),
);

/// Styles of the amounts: always tabular figures (section 3).
extension AmountTextStyle on TextStyle {
  /// This style for an amount, with tabular figures.
  TextStyle get amount =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// This style for an amount in a list: tabular figures, weight 600.
  TextStyle get listAmount => withWeight(amount, FontWeight.w600);
}
