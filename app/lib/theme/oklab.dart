import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// A colour in the OKLab space: lightness [l] from 0 to 1 and the two
/// opponent axes [a] (green–red) and [b] (blue–yellow).
///
/// In polar form (OKLCH) the axes become [chroma] and [hue]. The house
/// colours are computed here (section 9.2 of `docs/spec/stile.md`).
@immutable
class Oklab {
  const new(this.l, this.a, this.b);

  /// The OKLab coordinates of an sRGB [color]; its opacity is ignored.
  factory fromColor(Color color) {
    final r = _toLinear(color.r);
    final g = _toLinear(color.g);
    final b = _toLinear(color.b);
    final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return Oklab(
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    );
  }

  /// From lightness, [chroma] and [hue] in radians (OKLCH).
  factory fromLch(double l, double chroma, double hue) =>
      Oklab(l, chroma * math.cos(hue), chroma * math.sin(hue));

  /// The colour between [from] and [to] at [t], on a straight line in OKLab.
  factory lerp(Oklab from, Oklab to, double t) => Oklab(
    from.l + (to.l - from.l) * t,
    from.a + (to.a - from.a) * t,
    from.b + (to.b - from.b) * t,
  );

  final double l;
  final double a;
  final double b;

  /// How far a linear sRGB channel may leave the range 0–1 and still count
  /// as inside the gamut: less than half a step of an 8-bit channel.
  static const double _gamutTolerance = 1e-4;

  double get chroma => math.sqrt(a * a + b * b);

  /// Hue angle in radians.
  double get hue => math.atan2(b, a);

  /// This colour with another lightness.
  Oklab withLightness(double lightness) => Oklab(lightness, a, b);

  /// This colour with the hue turned by [radians]; lightness and chroma stay
  /// the same.
  Oklab rotated(double radians) => Oklab.fromLch(l, chroma, hue + radians);

  /// Linear sRGB channels, not clamped.
  ({double r, double g, double b}) get _linearSrgb {
    final l = math.pow(this.l + 0.3963377774 * a + 0.2158037573 * b, 3);
    final m = math.pow(this.l - 0.1055613458 * a - 0.0638541728 * b, 3);
    final s = math.pow(this.l - 0.0894841775 * a - 1.2914855480 * b, 3);
    return (
      r: 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      g: -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      b: -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    );
  }

  /// Whether sRGB can show this colour.
  bool get isInSrgbGamut {
    final (:r, :g, :b) = _linearSrgb;
    return _isInRange(r) && _isInRange(g) && _isInRange(b);
  }

  /// This colour if sRGB can show it; otherwise the closest one with the
  /// same lightness and hue and less chroma.
  Oklab fittedToSrgb() {
    if (isInSrgbGamut) return this;
    final hue = this.hue;
    var inside = 0.0;
    var outside = chroma;
    for (var step = 0; step < 24; step++) {
      final middle = (inside + outside) / 2;
      if (Oklab.fromLch(l, middle, hue).isInSrgbGamut) {
        inside = middle;
      } else {
        outside = middle;
      }
    }
    return Oklab.fromLch(l, inside, hue);
  }

  /// The opaque sRGB colour closest to this one, with 8 bits per channel.
  Color toColor() {
    final (:r, :g, :b) = _linearSrgb;
    return Color.fromARGB(255, _toByte(r), _toByte(g), _toByte(b));
  }

  @override
  bool operator ==(Object other) =>
      other is Oklab && other.l == l && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(l, a, b);

  @override
  String toString() => 'Oklab($l, $a, $b)';

  static bool _isInRange(double channel) =>
      channel >= -_gamutTolerance && channel <= 1 + _gamutTolerance;

  static int _toByte(double linear) =>
      (_fromLinear(linear.clamp(0, 1).toDouble()) * 255).round();

  /// sRGB transfer function, from an encoded channel to linear light.
  static double _toLinear(double channel) => channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

  /// sRGB transfer function, from linear light to an encoded channel.
  static double _fromLinear(double channel) => channel <= 0.0031308
      ? 12.92 * channel
      : 1.055 * math.pow(channel, 1 / 2.4) - 0.055;

  static double _cbrt(double value) => value < 0
      ? -math.pow(-value, 1 / 3).toDouble()
      : math.pow(value, 1 / 3).toDouble();
}
