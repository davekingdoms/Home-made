import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/features/startup/startup_screen.dart';
import 'package:homemade/features/startup/startup_state.dart';

/// Name of the query parameter that carries the screen asked for along the
/// startup steps.
const destinationParameter = 'from';

/// Path of the screen of the step of [startup]; null for the hub, where
/// nothing is missing. The household step is A7, or A10 with a pending
/// invite; A9 follows "Crea" of A8.
String? startupStepPath(StartupState startup) => switch (startup.step) {
  StartupStep.checking || StartupStep.unavailable => startupPath,
  StartupStep.signIn => screenByCode('A2').path,
  StartupStep.welcome => screenByCode('A3').path,
  StartupStep.household => screenByCode(startup.joining ? 'A10' : 'A7').path,
  StartupStep.invite => screenByCode('A9').path,
  StartupStep.location => screenByCode('A11').path,
  StartupStep.hub => null,
};

/// Paths of the steps the gate checks today: sign-in, first access and the
/// startup screen. Together with the household ([_householdPath] and its
/// sub-screens) they are never a destination to return to, and once their
/// step is done they give way to the screen asked for (or to the hub).
/// Location joins when PR 4.8 turns its step on; until then its screen is a
/// placeholder like the others.
///
/// The unlock (A1) is not a step: it covers the app from outside the router,
/// and no redirect leads to `/unlock`, which shows A1 only as a preview.
final Set<String> _gatePaths = {
  startupPath,
  screenByCode('A2').path!,
  screenByCode('A3').path!,
};

/// Path of the household step (A7), parent of A8–A10. A9 and A10 are also
/// the screens of steps of their own: after "Crea", and with a pending
/// invite.
final String _householdPath = screenByCode('A7').path!;

/// Whether [path] is a screen of the gate: one of [_gatePaths], or the
/// household with its sub-screens.
bool _isGatePath(String path) =>
    _gatePaths.contains(path) ||
    path == _householdPath ||
    path.startsWith('$_householdPath/');

/// Where the router sends [location] in the startup state [startup]; null
/// to show it.
///
/// While a step is missing every screen leads to the screen of that step
/// (and its sub-screens); the screen asked for travels in the
/// [destinationParameter] and opens when nothing is missing, if it is not
/// itself a screen of the gate. After "Esci" it is forgotten.
String? startupRedirect(StartupState startup, Uri location) {
  final path = location.path;
  final destination = _isGatePath(path)
      ? location.queryParameters[destinationParameter]
      : location.toString();
  final target = startupStepPath(startup);
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
  if (_isGatePath(path)) return _admitted(destination) ?? '/';
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
  if (_isGatePath(uri.path)) return null;
  return destination;
}
