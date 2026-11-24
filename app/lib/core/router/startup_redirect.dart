import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/features/startup/startup_screen.dart';
import 'package:homemade/features/startup/startup_state.dart';

/// Name of the query parameter that carries the screen asked for along the
/// startup steps.
const destinationParameter = 'from';

/// Path of the screen of [step]; null for the hub, where nothing is missing.
String? startupStepPath(StartupStep step) => switch (step) {
  StartupStep.checking || StartupStep.unavailable => startupPath,
  StartupStep.signIn => screenByCode('A2').path,
  StartupStep.welcome => screenByCode('A3').path,
  StartupStep.household => screenByCode('A7').path,
  StartupStep.location => screenByCode('A11').path,
  StartupStep.hub => null,
};

/// Paths of the steps the gate checks today: sign-in, first access and the
/// startup screen. They are never a destination to return to, and once
/// their step is done they give way to the screen asked for (or to the
/// hub). Household and location join when PRs 4.6 and 4.8 turn their steps
/// on; until then their screens are placeholders like the others.
///
/// The unlock (A1) is not a step: it covers the app from outside the router,
/// and no redirect leads to `/unlock`, which shows A1 only as a preview.
final Set<String> _gatePaths = {
  startupPath,
  screenByCode('A2').path!,
  screenByCode('A3').path!,
};

/// Where the router sends [location] in the startup state [startup]; null
/// to show it.
///
/// While a step is missing every screen leads to the screen of that step
/// (and its sub-screens); the screen asked for travels in the
/// [destinationParameter] and opens when nothing is missing, if it is not
/// itself a screen of the gate. After "Esci" it is forgotten.
String? startupRedirect(StartupState startup, Uri location) {
  final path = location.path;
  final destination = _gatePaths.contains(path)
      ? location.queryParameters[destinationParameter]
      : location.toString();
  final target = startupStepPath(startup.step);
  if (target != null) {
    if (path == target || path.startsWith('$target/')) return null;
    final keep = startup.arrival == SignInArrival.signedOut
        ? null
        : _admitted(destination);
    return Uri(
      path: target,
      queryParameters: keep == null ? null : {destinationParameter: keep},
    ).toString();
  }
  if (_gatePaths.contains(path)) return _admitted(destination) ?? '/';
  return null;
}

/// [destination] if the app may open it after the startup steps: a path of
/// the app other than the hub and the screens of the gate.
String? _admitted(String? destination) {
  if (destination == null || !destination.startsWith('/')) return null;
  if (destination.startsWith('//')) return null;
  final uri = Uri.tryParse(destination);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (uri.path == '/' && !uri.hasQuery) return null;
  if (_gatePaths.contains(uri.path)) return null;
  return destination;
}
