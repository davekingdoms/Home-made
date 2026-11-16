import 'package:homemade/theme/oklab.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Time of the day the hub house is drawn in.
enum CasaTime {
  night,

  /// Dawn and sunset share the same colours.
  dawn,

  day,
}

/// Colours of the hub house, computed with the rule of section 9.2 of
/// `docs/spec/stile.md` from the Teal roles at night.
///
/// Phase 1 only draws the night ([CasaColors.of] with its default time); day
/// and dawn are ready for the variable sky of phase 1b.
@immutable
class CasaColors extends ThemeExtension<CasaColors> {
  const new(this._colors);

  /// The house colours of [palette] at [time].
  factory of(AppPalette palette, [CasaTime time = CasaTime.night]) =>
      CasaColors({
        for (final role in CasaRole.values)
          role: compute(role, palette, time).toColor(),
      });

  final Map<CasaRole, Color> _colors;

  /// Below this chroma a role is almost grey and keeps its hue.
  static const double greyChroma = 0.008;

  /// How far dawn and sunset lean towards [casaSunset].
  static const double sunsetAmount = 0.12;

  /// The colour of [role].
  Color operator [](CasaRole role) => _colors[role]!;

  /// The colour of [role] for [palette] at [time], before it is rounded to
  /// 8 bits per channel. Always inside the sRGB gamut.
  static Oklab compute(CasaRole role, AppPalette palette, CasaTime time) {
    final night = rotateHue(
      Oklab.fromColor(casaTealNight[role]!),
      paletteHueShift(palette),
    );
    if (time == CasaTime.night) return night;

    final day = daylight(night);
    if (time == CasaTime.day) return day;

    final between = Oklab.lerp(night, day, 0.5);
    final sunset = Oklab.fromColor(casaSunset);
    return Oklab.lerp(between, sunset, sunsetAmount).fittedToSrgb();
  }

  /// Hue of the primary of [palette] minus the hue of the Teal primary, in
  /// radians. The primaries are the night ones, as the base roles are.
  static double paletteHueShift(AppPalette palette) =>
      Oklab.fromColor(paletteTokens[palette]!.dark.primary).hue -
      Oklab.fromColor(tealDark.primary).hue;

  /// [color] with the hue turned by [radians], same lightness and chroma
  /// (less chroma if sRGB cannot show it). Almost grey colours are not
  /// turned.
  static Oklab rotateHue(Oklab color, double radians) {
    if (color.chroma < greyChroma) return color;
    return color.rotated(radians).fittedToSrgb();
  }

  /// The day version of a night colour: lighter, same chroma.
  static Oklab daylight(Oklab night) =>
      night.withLightness(0.20 + 0.80 * night.l).fittedToSrgb();

  @override
  CasaColors copyWith({Map<CasaRole, Color>? colors}) =>
      CasaColors({..._colors, ...?colors});

  @override
  CasaColors lerp(CasaColors? other, double t) {
    if (other == null) return this;
    return CasaColors({
      for (final role in CasaRole.values)
        role: Color.lerp(this[role], other[role], t)!,
    });
  }
}

extension CasaColorsContext on BuildContext {
  /// The [CasaColors] of the current theme.
  CasaColors get casaColors => Theme.of(this).extension<CasaColors>()!;
}
