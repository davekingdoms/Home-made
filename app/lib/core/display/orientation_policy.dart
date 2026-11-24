import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:homemade/theme/dimens.dart';

/// Orientations of the app on a display of [physicalSize] pixels with
/// [devicePixelRatio] (`docs/spec/navigazione.md`, section 5): portrait only
/// on a phone, whose display has its short side under
/// [AppBreakpoints.medium] dp; on a tablet none is preferred, so every
/// orientation the system allows.
///
/// It looks at the display, not at the window: a tablet in split screen
/// keeps turning.
List<DeviceOrientation> preferredOrientations(
  Size physicalSize,
  double devicePixelRatio,
) {
  final shortSide = physicalSize.shortestSide / devicePixelRatio;
  return shortSide < AppBreakpoints.medium
      ? const [DeviceOrientation.portraitUp]
      : const [];
}

/// Applies [preferredOrientations] to the display of the app at start, and
/// again when the metrics change: a foldable that opens or closes changes
/// display. Nothing is locked in the Android manifest, which would also
/// lock the tablets up to Android 15.
class OrientationPolicy with WidgetsBindingObserver {
  /// The orientations last sent to the system.
  List<DeviceOrientation>? _applied;

  /// Applies the policy now and at every change of the metrics.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _apply();
  }

  @override
  void didChangeMetrics() => _apply();

  void _apply() {
    final display =
        WidgetsBinding.instance.platformDispatcher.implicitView?.display;
    // Before the system describes the display there is nothing to decide.
    if (display == null || display.size.isEmpty) return;
    final orientations = preferredOrientations(
      display.size,
      display.devicePixelRatio,
    );
    if (listEquals(orientations, _applied)) return;
    _applied = orientations;
    unawaited(SystemChrome.setPreferredOrientations(orientations));
  }
}
