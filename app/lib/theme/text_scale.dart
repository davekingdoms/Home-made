import 'package:material_ui/material_ui.dart';

/// Limits of the system text size (section 7 of `docs/spec/stile.md`).
abstract final class AppTextScale {
  /// Limit in the screens that scroll: 200%.
  static const double max = 2;

  /// Limit in the hub, which does not scroll: 130%.
  static const double hubMax = 1.3;

  /// Limit of the labels of the navigation bars: 130%, the one Material
  /// gives the bottom bar, which the side bar follows.
  static const double barLabelMax = 1.3;

  /// Lines that the helper and error texts of a text field may take before
  /// they are cut, enough for a message at [max].
  static const int maxFieldMessageLines = 5;

  /// [child] with the system text size limited to [maxScaleFactor].
  ///
  /// The app wraps every screen with the default limit; the hub wraps itself
  /// again with [hubMax].
  static Widget clamp({required Widget child, double maxScaleFactor = max}) =>
      MediaQuery.withClampedTextScaling(
        maxScaleFactor: maxScaleFactor,
        child: child,
      );

  /// The text scaler of [context], limited to [hubMax].
  static TextScaler hubScalerOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: hubMax);
}
