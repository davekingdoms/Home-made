import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/placeholder_route.dart';

/// Unlock (A1), sign-in (A2) and first access (A3).
List<RouteBase> authRoutes() => [
  placeholderRoute('A1', path: '/unlock'),
  placeholderRoute('A2', path: '/sign-in'),
  placeholderRoute('A3', path: '/welcome'),
];
