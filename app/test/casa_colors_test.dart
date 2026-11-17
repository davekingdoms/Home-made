import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/theme/casa_colors.dart';
import 'package:homemade/theme/oklab.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/spec.dart';

/// Every colour written in the tokens: the six combinations, the fixed
/// colours and the house.
List<Color> _tokenColors() => [
  for (final (palette, brightness) in combinations)
    ...tokensOf(palette, brightness).byRole.values,
  ...casaTealNight.values,
  nastroGiallo,
  nastroNero,
  counterBadgeDark,
  onCounterBadgeDark,
  casaSunset,
];

/// Opaque sRGB colours spread over the whole cube, greys included.
List<Color> _colorGrid() => [
  for (var r = 0; r <= 255; r += 17)
    for (var g = 0; g <= 255; g += 17)
      for (var b = 0; b <= 255; b += 17) Color.fromARGB(255, r, g, b),
  for (var v = 0; v <= 255; v++) Color.fromARGB(255, v, v, v),
];

Color _opaque(Color color) => color.withValues(alpha: 1);

/// Matches an angle in radians equal to [expected], whole turns apart.
Matcher _sameAngleAs(double expected) => predicate<double>((angle) {
  final turns = (angle - expected) / (2 * math.pi);
  return (turns - turns.roundToDouble()).abs() < 1e-6;
}, 'the same angle as $expected');

void main() {
  group('OKLab', () {
    test('sRGB to OKLab and back loses nothing', () {
      for (final color in [..._tokenColors(), ..._colorGrid()]) {
        expect(
          Oklab.fromColor(color).toColor(),
          _opaque(color),
          reason: '$color',
        );
      }
    });

    test('black, white and greys have no chroma', () {
      expect(Oklab.fromColor(Colors.black).l, closeTo(0, 1e-6));
      expect(Oklab.fromColor(Colors.white).l, closeTo(1, 1e-6));
      for (var v = 0; v <= 255; v += 15) {
        final grey = Oklab.fromColor(Color.fromARGB(255, v, v, v));
        expect(grey.chroma, lessThan(1e-4), reason: '$v');
      }
    });

    test('rotating the hue keeps lightness and chroma', () {
      final color = Oklab.fromColor(tealDark.primaryContainer);
      final rotated = color.rotated(math.pi / 3);

      expect(rotated.l, closeTo(color.l, 1e-12));
      expect(rotated.chroma, closeTo(color.chroma, 1e-12));
      expect(rotated.hue, _sameAngleAs(color.hue + math.pi / 3));
    });

    test('fitting to sRGB only reduces the chroma', () {
      // More chroma than sRGB can show at this lightness.
      final vivid = Oklab.fromLch(0.7, 0.4, 2.5);
      expect(vivid.isInSrgbGamut, isFalse);

      final fitted = vivid.fittedToSrgb();
      expect(fitted.isInSrgbGamut, isTrue);
      expect(fitted.l, closeTo(vivid.l, 1e-12));
      expect(fitted.hue, _sameAngleAs(vivid.hue));
      expect(fitted.chroma, lessThan(vivid.chroma));
      // As much chroma as fits: a little more is already out.
      expect(
        Oklab.fromLch(
          fitted.l,
          fitted.chroma + 0.005,
          fitted.hue,
        ).isInSrgbGamut,
        isFalse,
      );

      final inside = Oklab.fromColor(tealDark.primary);
      expect(inside.fittedToSrgb(), inside);
    });
  });

  group('house colours', () {
    final spec = readCasaRoles();

    test('the roles are those of section 9.2, in order', () {
      expect(CasaRole.values.map((role) => role.name), spec.keys);
      expect(spec, hasLength(38));
      expect(
        casaTealNight.map((role, color) => MapEntry(role.name, color)),
        spec,
      );
    });

    test('Teal at night gives exactly the roles of section 9.2', () {
      final casa = CasaColors.of(AppPalette.teal);
      for (final role in CasaRole.values) {
        expect(casa[role], spec[role.name], reason: role.name);
      }
      expect(CasaColors.paletteHueShift(AppPalette.teal), 0);
    });

    test('almost grey roles are not rotated', () {
      const turn = math.pi / 2;
      final greys = [
        for (var v = 0; v <= 255; v += 51)
          Oklab.fromColor(Color.fromARGB(255, v, v, v)),
        // Barely tinted, under the threshold.
        const Oklab(0.5, 0.005, -0.004),
        Oklab.fromLch(0.3, CasaColors.greyChroma - 0.0001, 1),
      ];
      for (final grey in greys) {
        expect(CasaColors.rotateHue(grey, turn), grey, reason: '$grey');
      }

      // Above the threshold the hue turns.
      final tinted = Oklab.fromLch(0.3, CasaColors.greyChroma + 0.0001, 1);
      final rotated = CasaColors.rotateHue(tinted, turn);
      expect(rotated, isNot(tinted));
      expect(rotated.hue, _sameAngleAs(tinted.hue + turn));
    });

    test('the other palettes turn the hue by that of their primary', () {
      for (final palette in [AppPalette.dollari, AppPalette.mauriziani]) {
        final shift = CasaColors.paletteHueShift(palette);
        final primaryHue = Oklab.fromColor(paletteTokens[palette]!.dark.primary)
            .hue;
        final tealHue = Oklab.fromColor(tealDark.primary).hue;
        expect(shift, closeTo(primaryHue - tealHue, 1e-12));
        expect(shift, isNot(0));

        for (final role in CasaRole.values) {
          final teal = CasaColors.compute(
            role,
            AppPalette.teal,
            CasaTime.night,
          );
          final night = CasaColors.compute(role, palette, CasaTime.night);
          final reason = '${palette.name} ${role.name}';

          // Same lightness; same chroma, or less to stay inside sRGB.
          expect(night.l, closeTo(teal.l, 1e-9), reason: reason);
          expect(
            night.chroma,
            lessThanOrEqualTo(teal.chroma + 1e-9),
            reason: reason,
          );
          expect(night.hue, _sameAngleAs(teal.hue + shift), reason: reason);
        }
      }
    });

    test('no colour is out of the sRGB gamut', () {
      for (final palette in AppPalette.values) {
        for (final time in CasaTime.values) {
          for (final role in CasaRole.values) {
            final color = CasaColors.compute(role, palette, time);
            final reason = '${palette.name} ${time.name} ${role.name}';

            expect(color.isInSrgbGamut, isTrue, reason: reason);
            // Rounding to 8 bits moves it by less than a step.
            final rounded = Oklab.fromColor(color.toColor());
            expect(rounded.l, closeTo(color.l, 0.005), reason: reason);
            expect(rounded.a, closeTo(color.a, 0.005), reason: reason);
            expect(rounded.b, closeTo(color.b, 0.005), reason: reason);
          }
        }
      }
    });

    test('day is lighter, with the lightness of the rule', () {
      for (final palette in AppPalette.values) {
        for (final role in CasaRole.values) {
          final night = CasaColors.compute(role, palette, CasaTime.night);
          final day = CasaColors.compute(role, palette, CasaTime.day);
          final reason = '${palette.name} ${role.name}';

          expect(day.l, closeTo(0.20 + 0.80 * night.l, 1e-9), reason: reason);
          expect(
            day.chroma,
            lessThanOrEqualTo(night.chroma + 1e-9),
            reason: reason,
          );
        }
      }
    });

    test('dawn is between night and day, 12% towards the sunset colour', () {
      final sunset = Oklab.fromColor(casaSunset);
      for (final palette in AppPalette.values) {
        for (final role in CasaRole.values) {
          final night = CasaColors.compute(role, palette, CasaTime.night);
          final day = CasaColors.compute(role, palette, CasaTime.day);
          final dawn = CasaColors.compute(role, palette, CasaTime.dawn);
          final expected = Oklab.lerp(
            Oklab.lerp(night, day, 0.5),
            sunset,
            CasaColors.sunsetAmount,
          );
          final reason = '${palette.name} ${role.name}';

          expect(CasaColors.sunsetAmount, 0.12);
          expect(dawn.l, closeTo(expected.l, 1e-9), reason: reason);
          expect(dawn.hue, _sameAngleAs(expected.hue), reason: reason);
          expect(
            dawn.chroma,
            lessThanOrEqualTo(expected.chroma + 1e-9),
            reason: reason,
          );
        }
      }
    });

    test('the theme extension reads, copies and blends the roles', () {
      final teal = CasaColors.of(AppPalette.teal);
      final dollari = CasaColors.of(AppPalette.dollari);

      expect(teal.lerp(dollari, 0)[CasaRole.tetto], teal[CasaRole.tetto]);
      expect(teal.lerp(dollari, 1)[CasaRole.tetto], dollari[CasaRole.tetto]);
      expect(teal.lerp(null, 0.5), same(teal));

      final copy = teal.copyWith(colors: {CasaRole.tetto: Colors.black});
      expect(copy[CasaRole.tetto], Colors.black);
      expect(copy[CasaRole.muro], teal[CasaRole.muro]);
    });
  });
}
