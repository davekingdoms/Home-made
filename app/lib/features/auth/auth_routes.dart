import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/placeholder_route.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/welcome_screen.dart';

/// Unlock (A1), sign-in (A2) and first access (A3).
List<RouteBase> authRoutes() => [
  placeholderRoute('A1', path: '/unlock'),
  GoRoute(path: '/sign-in', builder: (context, state) => const SignInScreen()),
  GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
];
