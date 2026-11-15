import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/placeholder_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Route of the catalog screen [code], shown as a placeholder until the
/// screen is built.
///
/// [path] is the segment relative to the parent route; a test checks that the
/// full path matches the catalog. [embedded] is for the tabs of a section.
GoRoute placeholderRoute(
  String code, {
  required String path,
  GlobalKey<NavigatorState>? parentNavigatorKey,
  bool embedded = false,
  List<RouteBase> routes = const [],
}) {
  final entry = screenByCode(code);
  return GoRoute(
    path: path,
    parentNavigatorKey: parentNavigatorKey,
    builder: (context, state) =>
        PlaceholderScreen(entry: entry, embedded: embedded),
    routes: routes,
  );
}
