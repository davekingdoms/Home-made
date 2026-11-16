import 'package:material_ui/material_ui.dart';

/// Limits of the system text size (section 7 of `docs/spec/stile.md`).
abstract final class AppTextScale {
  /// Limit in the screens that scroll: 200%.
  static const double max = 2;

  /// Limit in the hub, which does not scroll: 130%.
  static const double hubMax = 1.3;

  /// [child] with the system text size limited to [maxScaleFactor].
  ///
  /// The app wraps every screen with the default limit; the hub wraps itself
  /// again with [hubMax].
  static Widget clamp({
    required Widget child,
    double maxScaleFactor = max,
  }) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: maxScaleFactor,
    child: child,
  );

  /// The text scaler of [context], limited to [hubMax].
  static TextScaler hubScalerOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: hubMax);
}
