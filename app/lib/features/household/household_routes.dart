import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/placeholder_route.dart';

/// Create or join a household (A7–A10).
RouteBase householdRoute() => placeholderRoute(
  'A7',
  path: '/household',
  routes: [
    placeholderRoute('A8', path: 'create'),
    placeholderRoute('A9', path: 'invite'),
    placeholderRoute('A10', path: 'join'),
  ],
);
