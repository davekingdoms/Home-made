import 'package:material_ui/material_ui.dart';

/// Durations from section 6 of `docs/spec/stile.md`.
abstract final class AppDurations {
  /// States and small changes.
  static const Duration short = Duration(milliseconds: 150);

  /// Sheets and expansions.
  static const Duration medium = Duration(milliseconds: 300);

  /// Screen transitions and the house.
  static const Duration long = Duration(milliseconds: 500);
}

/// The "emphasized" curves of Material 3.
abstract final class AppCurves {
  /// For what enters the screen.
  static const Curve enter = Easing.emphasizedDecelerate;

  /// For what leaves the screen.
  static const Curve exit = Easing.emphasizedAccelerate;
}

/// Timeline of a transition in which the outgoing content fades out before
/// the incoming one fades in ("fade through" and "shared axis" of
/// Material 3), as fractions of its duration.
///
/// With "reduce animations" both become short fades, without movement.
abstract final class TransitionTimeline {
  /// Fraction of [AppDurations.long] that a short fade takes.
  static const double _shortFade = 0.3;

  /// Opacity of the incoming content at [progress], which goes from 0 to 1.
  static double fadeIn(
    double progress, {
    required double start,
    required bool reduceMotion,
  }) {
    if (reduceMotion) {
      return const Interval(_shortFade / 2, _shortFade).transform(progress);
    }
    return Interval(start, 1, curve: AppCurves.enter).transform(progress);
  }

  /// Opacity of the outgoing content at [progress], which goes from 0 to 1.
  static double fadeOut(
    double progress, {
    required double end,
    required bool reduceMotion,
  }) {
    if (reduceMotion) {
      return 1 - const Interval(0, _shortFade / 2).transform(progress);
    }
    return 1 - Interval(0, end, curve: AppCurves.exit).transform(progress);
  }
}
